// ========================================
// MongoDB 初始化脚本
// 1. 创建应用用户（appuser）
// 2. 创建 Prometheus exporter 用户
// 3. 创建多环境数据库
// ========================================

const appDb = process.env.MONGO_INITDB_DATABASE || 'appdb';
const appUser = process.env.MONGO_APP_USER || 'appuser';
const appPassword = process.env.MONGO_APP_PASSWORD;

if (!appPassword) {
  throw new Error('MONGO_APP_PASSWORD not set');
}

// === 1. 创建应用用户 ===
db = db.getSiblingDB(appDb);
db.createUser({
  user: appUser,
  pwd: appPassword,
  roles: [
    { role: 'readWrite', db: appDb },
    { role: 'dbAdmin', db: appDb }
  ]
});
print('✅ app user ' + appUser + ' created on ' + appDb);

// === 2. 创建 Prometheus exporter 用户 ===
const exporterUser = process.env.MONGO_EXPORTER_USER || 'exporter';
const exporterPassword = process.env.MONGO_EXPORTER_PASSWORD;

if (exporterPassword) {
  db = db.getSiblingDB('admin');
  db.createUser({
    user: exporterUser,
    pwd: exporterPassword,
    roles: [
      { role: 'clusterMonitor', db: 'admin' },
      { role: 'read', db: 'local' }
    ]
  });
  print('✅ exporter user ' + exporterUser + ' created');
} else {
  print('MONGO_EXPORTER_PASSWORD not set, skipping exporter user');
}

// === 3. 初始化当前环境数据库 ===
// 每个环境为独立物理实例，只需初始化当前实例的应用数据库（appDb 即 MONGO_INITDB_DATABASE）
db = db.getSiblingDB(appDb);
db.createCollection('_init_marker');
print('✅ Database ' + appDb + ' initialized');
