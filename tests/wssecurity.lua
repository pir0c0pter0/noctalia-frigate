-- Run from the repository root: lua tests/wssecurity.lua
local mask = 0xffffffff
bit32 = bit32 or {
    band = function(a, b, ...)
        local v = (a & b) & mask
        for _, n in ipairs({ ... }) do v = (v & n) & mask end
        return v
    end,
    bor = function(a, b, ...)
        local v = (a | b) & mask
        for _, n in ipairs({ ... }) do v = (v | n) & mask end
        return v
    end,
    bxor = function(a, b, ...)
        local v = (a ~ b) & mask
        for _, n in ipairs({ ... }) do v = (v ~ n) & mask end
        return v
    end,
    bnot = function(a) return (~a) & mask end,
    lshift = function(a, n) return (a << n) & mask end,
    rshift = function(a, n) return (a & mask) >> n end,
    lrotate = function(a, n) return ((a << n) | ((a & mask) >> (32 - n))) & mask end,
}
local ws = assert(loadfile('WsSecurity.luau'))()
local function hex(s) return (s:gsub('.', function(c) return string.format('%02x', c:byte()) end)) end
assert(hex(ws.sha1('')) == 'da39a3ee5e6b4b0d3255bfef95601890afd80709')
assert(hex(ws.sha1('abc')) == 'a9993e364706816aba3e25717850c26c9cd0d89d')
assert(hex(ws.sha1(string.rep('a', 56))) == 'c2db330f6083854c99d4b5bfb6e8f29f201be699')
assert(hex(ws.sha1(string.rep('a', 1000000))) == '34aa973cd4c4daa4f61eeb2bdbad27316534016f')
assert(ws.base64('') == '' and ws.base64('f') == 'Zg==' and ws.base64('fo') == 'Zm8=' and ws.base64('foo') == 'Zm9v')
assert(ws.base64('\0\255\1') == 'AP8B')
local token = ws.usernameToken('a<&"\'b', 'secret', 'nonce', '2026-10-28T12:34:56Z')
assert(token:find('a&lt;&amp;&quot;&apos;b', 1, true))
assert(token:find('bm9uY2U=', 1, true))
assert(token:find('2026-10-28T12:34:56Z', 1, true))
assert(token:find('secret', 1, true) == nil)
assert(token:find('qXZRol78Vt7dAuiSSranp9LrYSs=', 1, true))
assert(ws.usernameToken('usuário', 'senhaá&', 'nonce', '2026-10-28T12:34:56Z'):find('8lnYMcGMSp01ZifC/ufq4M5CWSY=', 1, true))
assert(ws.usernameToken('bad\1name', 'secret', 'nonce', '2026-10-28T12:34:56Z') == nil)
print('WS-Security SHA-1, base64 and UsernameToken checks passed')
