// Fengari's CLI can print a Lua failure without a failing process exit code.
// Call the protected Lua API directly so assertions reliably fail the test run.
'use strict';
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const args = process.argv.slice(2);
if (!args.length) {
  process.stderr.write('Usage: node scripts/run-lua-test.js TEST.lua [arguments...]\n');
  process.exitCode = 2;
} else {
  try {
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    lua.lua_createtable(L, args.length, 0);
    args.forEach((value, index) => {
      lua.lua_pushstring(L, to_luastring(value));
      lua.lua_rawseti(L, -2, index);
    });
    lua.lua_setglobal(L, to_luastring('arg'));
    let result = lauxlib.luaL_loadfile(L, to_luastring(args[0]));
    if (result === lua.LUA_OK) result = lua.lua_pcall(L, 0, lua.LUA_MULTRET, 0);
    if (result !== lua.LUA_OK) {
      const message = lua.lua_tostring(L, -1);
      process.stderr.write((message ? to_jsstring(message) : 'Lua test failed') + '\n');
      process.exitCode = 1;
    }
    lua.lua_close(L);
  } catch (error) {
    process.stderr.write(String(error.stack || error) + '\n');
    process.exitCode = 1;
  }
}
