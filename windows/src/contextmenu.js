'use strict';
// Пункт «Конвертер…» в правом клике Проводника (реестр пользователя, права администратора не нужны)
const { run } = require('./util');

const KEYS = ['HKCU\\Software\\Classes\\*\\shell\\Konverter', 'HKCU\\Software\\Classes\\Directory\\shell\\Konverter'];

function commands(exe) {
  const list = [];
  for (const k of KEYS) {
    list.push(['add', k, '/ve', '/d', 'Конвертер…', '/f']);
    list.push(['add', k, '/v', 'Icon', '/d', exe, '/f']);
    list.push(['add', `${k}\\command`, '/ve', '/d', `"${exe}" --ctx "%1"`, '/f']);
  }
  return list;
}

async function enable(exe) { for (const a of commands(exe)) await run('reg', a); }
async function disable() { for (const k of KEYS) { try { await run('reg', ['delete', k, '/f']); } catch (e) { /* уже нет */ } } }

module.exports = { enable, disable, commands, KEYS };
