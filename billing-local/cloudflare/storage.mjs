export function durableDatabase(storage) {
  const execute = (sql, args = []) => storage.sql.exec(sql, ...args);
  return {
    exec(sql) { execute(sql).toArray(); },
    prepare(sql) {
      return {
        get(...args) { return execute(sql, args).toArray()[0]; },
        all(...args) { return execute(sql, args).toArray(); },
        run(...args) {
          execute(sql, args).toArray();
          return { changes: execute('SELECT changes() AS n').one().n };
        }
      };
    },
    transaction(callback) { return storage.transactionSync(callback); },
    close() {}
  };
}
