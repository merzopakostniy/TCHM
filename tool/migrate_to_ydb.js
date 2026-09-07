// Перенос данных из Firestore в YDB Яндекс Облака.
//
// Читает columns и machinists, отдаёт их служебной операции функции
// tchm-api, которая пишет в YDB. Firestore при этом только читается:
// старая база остаётся рабочей, пока люди не переедут.
//
// Учётные записи НЕ переносятся: в старой базе их 158 на 21 человека, все
// без депо и без почты — наследие анонимного входа. Люди регистрируются
// заново по ключам, которые уже на руках у руководителей.
//
// Запуск из корня проекта:
//   node tool/migrate_to_ydb.js --dry-run   — только показать, что найдено
//   node tool/migrate_to_ydb.js             — перенести

const {execFileSync} = require('child_process');
const os = require('os');
const path = require('path');
const {initializeApp, cert} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');

const DRY_RUN = process.argv.includes('--dry-run');
const FOLDER = 'b1gbmm8sm75e9gc1or56';
const FUNCTION = 'tchm-api';
const YC = path.join(os.homedir(), 'yandex-cloud', 'bin', 'yc');
// Депо по умолчанию: в старой базе одно депо, и у части записей поле
// depotId пустое — те самые, что мы видели в строке «Без депо».
const DEFAULT_DEPOT = 'tch16';

initializeApp({credential: cert(require('./serviceAccount.json'))});
const db = getFirestore();

function invoke(payload) {
  const out = execFileSync(
    YC,
    ['serverless', 'function', 'invoke', '--name', FUNCTION,
     '--folder-id', FOLDER, '--data', JSON.stringify(payload)],
    {encoding: 'utf8', maxBuffer: 64 * 1024 * 1024},
  );
  return JSON.parse(out);
}

const text = (value) => (value === undefined || value === null ? '' : String(value));

async function main() {
  console.log(DRY_RUN ? '— вхолостую, записи не будет —\n' : '— перенос в YDB —\n');

  const columnsSnap = await db.collection('columns').get();
  const machinistsSnap = await db.collection('machinists').get();

  const columns = columnsSnap.docs.map((doc) => {
    const d = doc.data();
    return {
      id: doc.id,
      depotId: text(d.depotId) || DEFAULT_DEPOT,
      number: Number(d.number) || 0,
      title: text(d.title),
      tchmName: text(d.tchmName),
      tchmPersonnelNumber: text(d.tchmPersonnelNumber),
      instructorName: text(d.instructorName),
    };
  });

  const machinists = machinistsSnap.docs.map((doc) => {
    const d = doc.data();
    return {
      id: doc.id,
      depotId: text(d.depotId) || DEFAULT_DEPOT,
      columnId: text(d.columnId),
      fullName: text(d.fullName),
      classRank: text(d.classRank),
      workStart: text(d.workStart),
      ticket: text(d.ticket),
      kip: text(d.kip),
      tra: text(d.tra),
      atz: text(d.atz),
      coupling: text(d.coupling),
      vn: text(d.vn),
      notes: text(d.notes),
      kipExtensionMonths: Number(d.kipExtensionMonths) || 0,
      kipExtensionOrder: text(d.kipExtensionOrder),
      updatedBy: text(d.updatedBy),
    };
  });

  const byDepot = {};
  for (const m of machinists) byDepot[m.depotId] = (byDepot[m.depotId] || 0) + 1;
  const orphans = machinists.filter((m) => !columns.some((c) => c.id === m.columnId));

  console.log(`колонн:     ${columns.length}`);
  console.log(`машинистов: ${machinists.length}`);
  console.log(`по депо:    ${JSON.stringify(byDepot)}`);
  if (orphans.length) {
    console.log(`ВНИМАНИЕ: машинистов без существующей колонны — ${orphans.length}`);
  }

  if (DRY_RUN) {
    console.log('\nничего не записано');
    return;
  }

  // Пишем частями: одно тело запроса на сотню записей, чтобы не упереться
  // в ограничение размера вызова функции.
  const chunk = (items, size) => {
    const out = [];
    for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
    return out;
  };

  let written = 0;
  for (const part of chunk(columns, 100)) {
    const res = invoke({admin: {action: 'import_columns', columns: part}});
    if (res.error) throw new Error(res.error);
    written += res.written;
  }
  console.log(`колонн записано:     ${written}`);

  written = 0;
  for (const part of chunk(machinists, 100)) {
    const res = invoke({admin: {action: 'import_machinists', machinists: part}});
    if (res.error) throw new Error(res.error);
    written += res.written;
  }
  console.log(`машинистов записано: ${written}`);

  const stats = invoke({admin: {action: 'stats'}});
  console.log('\nв YDB сейчас:', JSON.stringify(stats));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
