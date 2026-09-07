// Run only against the local emulator; never connects to a real project.
const fs = require('fs');
const path = require('path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, updateDoc, getDoc, deleteDoc} = require('firebase/firestore');

(async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-tchm-release',
    firestore: {host: '127.0.0.1', port: 18080,
      rules: fs.readFileSync(path.join(__dirname, '../firestore.rules'), 'utf8')},
  });
  let checks = 0;
  const denied = async operation => { await assertFails(operation); checks++; };
  const allowed = async operation => { await assertSucceeds(operation); checks++; };
  try {
    await env.withSecurityRulesDisabled(async context => {
      const db = context.firestore();
      for (const role of ['viewer', 'tchm', 'operator', 'admin', 'developer']) {
        await setDoc(doc(db, 'users', role), {role, status: 'active', depotId: 'tch16', personnelNumber: '1000'});
      }
      for (const status of ['pending', 'disabled']) {
        await setDoc(doc(db, 'users', status), {role: 'tchm', status, depotId: 'tch16'});
      }
      await setDoc(doc(db, 'users', 'legacy'), {role: 'tchm'});
      await setDoc(doc(db, 'users', 'legacy-null'), {role: 'viewer', depotId: null});
      await setDoc(doc(db, 'users', 'legacy-developer'), {role: 'developer', status: 'active'});
      await setDoc(doc(db, 'columns', 'own'), {depotId: 'tch16', title: 'Own'});
      await setDoc(doc(db, 'columns', 'foreign'), {depotId: 'tch08_bl', title: 'Foreign'});
    });
    const newUser = env.authenticatedContext('new', {email_verified: true}).firestore();
    for (const role of ['viewer', 'tchm', 'admin', 'developer']) {
      await denied(setDoc(doc(newUser, 'users', 'new'), {role, status: 'active', displayName: 'Разработчик', personnelNumber: '1916', depotId: 'tch16'}));
    }
    for (const role of ['viewer', 'tchm', 'operator', 'admin', 'developer']) {
      const db = env.authenticatedContext(role).firestore();
      for (const change of [{role: role === 'developer' ? 'admin' : 'developer'}, {depotId: 'tch08_bl'}, {assignedColumnId: 'foreign'}, {personnelNumber: '1916'}]) {
        await denied(updateDoc(doc(db, 'users', role), change));
      }
      await denied(updateDoc(doc(db, 'users', role === 'viewer' ? 'tchm' : 'viewer'), {role: 'developer'}));
      await denied(setDoc(doc(db, 'roster', 'new'), {depotId: 'tch16', role: 'developer'}));
    }
    const tchm = env.authenticatedContext('tchm').firestore();
    const admin = env.authenticatedContext('admin').firestore();
    const dev = env.authenticatedContext('developer').firestore();
    await allowed(updateDoc(doc(tchm, 'columns', 'own'), {title: 'Edited'}));
    await denied(getDoc(doc(tchm, 'columns', 'foreign')));
    await denied(updateDoc(doc(tchm, 'columns', 'foreign'), {depotId: 'tch16'}));
    await denied(updateDoc(doc(tchm, 'users', 'viewer'), {status: 'disabled'}));
    await allowed(getDoc(doc(admin, 'columns', 'foreign')));
    await allowed(updateDoc(doc(admin, 'users', 'viewer'), {status: 'disabled'}));
    await denied(updateDoc(doc(admin, 'users', 'developer'), {status: 'disabled'}));
    await denied(deleteDoc(doc(admin, 'users', 'developer')));
    await denied(setDoc(doc(admin, 'config', 'app'), {writesBlocked: true, readsBlocked: true}));
    for (const status of ['pending', 'disabled']) {
      const db = env.authenticatedContext(status, {email_verified: true}).firestore();
      await denied(getDoc(doc(db, 'columns', 'own')));
      await denied(updateDoc(doc(db, 'users', status), {status: 'active'}));
    }
    await denied(getDoc(doc(env.authenticatedContext('legacy').firestore(), 'columns', 'own')));
    await denied(getDoc(doc(env.authenticatedContext('legacy').firestore(), 'columns', 'foreign')));
    await denied(getDoc(doc(env.authenticatedContext('legacy-null').firestore(), 'columns', 'own')));
    const legacyDev = env.authenticatedContext('legacy-developer').firestore();
    await denied(getDoc(doc(legacyDev, 'columns', 'own')));
    await denied(setDoc(doc(legacyDev, 'config', 'app'), {writesBlocked: false, readsBlocked: false}));
    await allowed(setDoc(doc(dev, 'config', 'app'), {writesBlocked: true, readsBlocked: false}));
    await allowed(getDoc(doc(tchm, 'columns', 'own')));
    await denied(updateDoc(doc(tchm, 'columns', 'own'), {title: 'Blocked'}));
    await denied(updateDoc(doc(dev, 'columns', 'own'), {title: 'Blocked'}));
    await allowed(setDoc(doc(dev, 'config', 'app'), {writesBlocked: false, readsBlocked: true}));
    await denied(getDoc(doc(admin, 'columns', 'own')));
    await allowed(getDoc(doc(dev, 'columns', 'own')));
    await allowed(setDoc(doc(dev, 'config', 'app'), {writesBlocked: false, readsBlocked: false}));
    console.log(`${checks} Firestore security checks passed`);
  } finally {
    await env.cleanup();
  }
})().catch(error => { console.error(error); process.exit(1); });
