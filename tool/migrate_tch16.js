// Миграция ТЧ-16 на мультидепо.
//
// Делает одно: проставляет depotId колоннам и машинистам, чтобы данные
// не потерялись после разделения по депо. Ничего не удаляет и не
// перезаписывает — только дописывает поле.
//
// Профили пользователей не трогаем: люди регистрируются заново по почте и
// роль выбирают сами. Старые профили останутся без депо и увидят экран
// «Депо не указано» с предложением зарегистрироваться.
//
// Запуск и подготовка — см. migrate_tch16.md.

const {initializeApp, applicationDefault} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');

const DEPOT_ID = 'tch16';
const DRY_RUN = process.argv.includes('--dry-run');

initializeApp({credential: applicationDefault()});
const db = getFirestore();

async function stampDepot(collection) {
  const snapshot = await db.collection(collection).get();
  let touched = 0;
  let batch = db.batch();
  let pending = 0;

  for (const doc of snapshot.docs) {
    if (doc.get('depotId') === DEPOT_ID) continue;
    touched += 1;
    if (DRY_RUN) continue;
    batch.set(doc.ref, {depotId: DEPOT_ID}, {merge: true});
    pending += 1;
    // Firestore не принимает больше 500 операций в одной пачке.
    if (pending === 400) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (!DRY_RUN && pending > 0) await batch.commit();

  const verb = DRY_RUN ? 'будет проставлено' : 'проставлено';
  console.log(`${collection}: ${verb} ${touched} из ${snapshot.size}`);
}

(async () => {
  console.log(DRY_RUN ? '— вхолостую, записи не будет —\n' : '— запись в базу —\n');
  await stampDepot('columns');
  await stampDepot('machinists');
  console.log('\nготово');
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
