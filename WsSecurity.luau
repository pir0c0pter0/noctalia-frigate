--!nonstrict
local band, bor, bxor = bit32.band, bit32.bor, bit32.bxor
local bnot, lshift, rshift, lrotate = bit32.bnot, bit32.lshift, bit32.rshift, bit32.lrotate

local function sha1(input)
    local length = #input * 8
    local suffix = { string.char(128), string.rep('\0', (55 - #input) % 64) }
    local high = math.floor(length / 4294967296)
    local low = length % 4294967296
    for _, part in ipairs({ high, low }) do
        for shift = 24, 0, -8 do suffix[#suffix + 1] = string.char(band(rshift(part, shift), 255)) end
    end
    local padded = input .. table.concat(suffix)
    local h0, h1, h2, h3, h4 = 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0
    for offset = 1, #padded, 64 do
        local w = {}
        for i = 0, 15 do
            local j = offset + i * 4
            local a, b, c, d = padded:byte(j, j + 3)
            w[i] = bor(lshift(a, 24), lshift(b, 16), lshift(c, 8), d)
        end
        for i = 16, 79 do w[i] = lrotate(bxor(w[i - 3], w[i - 8], w[i - 14], w[i - 16]), 1) end
        local a, b, c, d, e = h0, h1, h2, h3, h4
        for i = 0, 79 do
            local f, k
            if i < 20 then f, k = bor(band(b, c), band(bnot(b), d)), 0x5a827999
            elseif i < 40 then f, k = bxor(b, c, d), 0x6ed9eba1
            elseif i < 60 then f, k = bor(band(b, c), band(b, d), band(c, d)), 0x8f1bbcdc
            else f, k = bxor(b, c, d), 0xca62c1d6 end
            local t = (lrotate(a, 5) + f + e + k + w[i]) % 4294967296
            a, b, c, d, e = t, a, lrotate(b, 30), c, d
        end
        h0, h1, h2, h3, h4 = (h0 + a) % 4294967296, (h1 + b) % 4294967296,
            (h2 + c) % 4294967296, (h3 + d) % 4294967296, (h4 + e) % 4294967296
    end
    local out = {}
    for _, part in ipairs({ h0, h1, h2, h3, h4 }) do
        for shift = 24, 0, -8 do out[#out + 1] = string.char(band(rshift(part, shift), 255)) end
    end
    return table.concat(out)
end

local function base64(input)
    local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local result = {}
    for i = 1, #input, 3 do
        local a, b, c = input:byte(i, i + 2)
        local value = a * 65536 + (b or 0) * 256 + (c or 0)
        local function char(n) return alphabet:sub(n + 1, n + 1) end
        result[#result + 1] = char(math.floor(value / 262144) % 64)
        result[#result + 1] = char(math.floor(value / 4096) % 64)
        result[#result + 1] = b and char(math.floor(value / 64) % 64) or '='
        result[#result + 1] = c and char(value % 64) or '='
    end
    return table.concat(result)
end

local function escape(value)
    if value:find('[%z\1-\8\11\12\14-\31]') then return nil end
    return (value:gsub('[&<>"\']', { ['&'] = '&amp;', ['<'] = '&lt;', ['>'] = '&gt;',
        ['"'] = '&quot;', ["'"] = '&apos;' }))
end

local function usernameToken(username, password, nonce, created)
    local name = escape(username)
    local timestamp = escape(created)
    if not name or not timestamp then return nil end
    local digest = base64(sha1(nonce .. created .. password))
    return '<wsse:Security s:mustUnderstand="1"><wsse:UsernameToken><wsse:Username>' .. name
        .. '</wsse:Username><wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">'
        .. digest .. '</wsse:Password><wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">'
        .. base64(nonce) .. '</wsse:Nonce><wsu:Created>' .. timestamp
        .. '</wsu:Created></wsse:UsernameToken></wsse:Security>'
end

return { sha1 = sha1, base64 = base64, usernameToken = usernameToken }
