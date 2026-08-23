const DB_NAME = 'veiltalk-files';
const STORE = 'files';
const OPFS_DIR = 'veiltalk-received';

function openDb() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE)) {
        const store = db.createObjectStore(STORE, { keyPath: 'id' });
        store.createIndex('roomId', 'roomId');
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function transact(mode, work) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, mode);
    const store = tx.objectStore(STORE);
    let result;
    try { result = work(store); } catch (error) { db.close(); reject(error); return; }
    tx.oncomplete = () => { db.close(); resolve(result); };
    tx.onerror = () => { db.close(); reject(tx.error); };
  });
}

export function putFile({ id, roomId, name, type, blob }) {
  return transact('readwrite', store => store.put({ id, roomId, name, type, blob, savedAt: Date.now() }));
}

async function opfsDirectory(create = true) {
  if (!navigator.storage?.getDirectory) return null;
  const root = await navigator.storage.getDirectory();
  return root.getDirectoryHandle(OPFS_DIR, { create });
}

function opfsName(id) {
  return `file-${String(id).replace(/[^a-zA-Z0-9_-]/g, '')}`;
}

export async function createIncomingFile(id) {
  const directory = await opfsDirectory(true);
  if (!directory) return null;
  const name = opfsName(id);
  const handle = await directory.getFileHandle(name, { create:true });
  const writer = await handle.createWritable({ keepExistingData:false });
  return { name, writer };
}

export async function commitIncomingFile({ id, roomId, name, type, opfs, size }) {
  if (!opfs?.writer) throw new Error('OPFS_NOT_READY');
  await opfs.writer.close();
  await transact('readwrite', store => store.put({ id, roomId, name, type, opfsName:opfs.name, size, savedAt:Date.now() }));
}

export async function abortIncomingFile(opfs) {
  if (!opfs) return;
  try { await opfs.writer?.abort(); } catch (_) {}
  try {
    const directory = await opfsDirectory(false);
    await directory?.removeEntry(opfs.name);
  } catch (_) {}
}

export async function getFile(id) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, 'readonly');
    const request = tx.objectStore(STORE).get(id);
    request.onsuccess = async () => {
      const record = request.result || null;
      db.close();
      if (!record?.opfsName) return resolve(record);
      try {
        const directory = await opfsDirectory(false);
        const handle = await directory.getFileHandle(record.opfsName);
        const blob = await handle.getFile();
        resolve({ ...record, blob });
      } catch (_) {
        resolve(null);
      }
    };
    request.onerror = () => { db.close(); reject(request.error); };
  });
}

export async function deleteRoomFiles(roomId) {
  const db = await openDb();
  const opfsNames = [];
  await new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, 'readwrite');
    const index = tx.objectStore(STORE).index('roomId');
    const request = index.openCursor(IDBKeyRange.only(roomId));
    request.onsuccess = () => {
      const cursor = request.result;
      if (!cursor) return;
      if (cursor.value?.opfsName) opfsNames.push(cursor.value.opfsName);
      cursor.delete();
      cursor.continue();
    };
    tx.oncomplete = () => { db.close(); resolve(); };
    tx.onerror = () => { db.close(); reject(tx.error); };
  });
  if (!opfsNames.length) return;
  try {
    const directory = await opfsDirectory(false);
    await Promise.all(opfsNames.map(name => directory.removeEntry(name).catch(() => {})));
  } catch (_) {}
}
