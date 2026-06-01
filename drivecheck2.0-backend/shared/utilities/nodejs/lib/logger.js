const log = (level, msg, extra) => {
  const line = { level, msg, ...(extra && { extra }), ts: new Date().toISOString() };
  console.log(JSON.stringify(line));
};

module.exports = {
  info: (msg, extra) => log('info', msg, extra),
  warn: (msg, extra) => log('warn', msg, extra),
  error: (msg, extra) => log('error', msg, extra),
};
