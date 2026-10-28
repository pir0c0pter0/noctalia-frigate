--!nonstrict
-- Parse bounded SOAP XML without expanding custom entities or loading external data.
local function parseDocument(input)
    if type(input) ~= "string" or #input > 262144 or not utf8.len(input) or input:find("[%z\1-\8\11\12\14-\31]") then error("invalid XML") end
    if input:sub(1, 3) == "\239\187\191" then input = input:sub(4) end
    local position, stack, root, count = 1, {}, nil, 0
    local predefined = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'" }

    local function decode(value)
        local result, last = {}, 1
        while true do
            local first = value:find("&", last, true)
            if not first then table.insert(result, value:sub(last)); break end
            table.insert(result, value:sub(last, first - 1))
            local finish = value:find(";", first + 1, true)
            if not finish then error("invalid entity") end
            local entity = value:sub(first + 1, finish - 1)
            local replacement = predefined[entity]
            if not replacement then
                local digits = entity:match("^#(%d+)$")
                local hex = entity:match("^#x([%da-fA-F]+)$")
                local point = digits and tonumber(digits) or (hex and tonumber(hex, 16))
                if not point or not (point == 9 or point == 10 or point == 13 or
                    (point >= 32 and point <= 55295) or (point >= 57344 and point <= 65533) or
                    (point >= 65536 and point <= 1114111)) then error("invalid entity") end
                replacement = utf8.char(point)
            end
            table.insert(result, replacement)
            last = finish + 1
        end
        return table.concat(result)
    end

    local function append(value, literal)
        local node = stack[#stack]
        if not node then
            if value:find("%S") then error("text outside root") end
        else
            if not literal and value:find("]]>", 1, true) then error("invalid text") end
            node.text = node.text .. (literal and value or decode(value))
        end
    end

    local function validName(name)
        local first, second = name:match("^([^:]+):([^:]+)$")
        if first then return first:match("^[%a_][%w_.-]*$") ~= nil and second:match("^[%a_][%w_.-]*$") ~= nil end
        return name:match("^[%a_][%w_.-]*$") ~= nil
    end

    while position <= #input do
        local start = input:find("<", position, true)
        if not start then append(input:sub(position), false); break end
        append(input:sub(position, start - 1), false)
        if input:sub(start, start + 3) == "<!--" then
            local finish = input:find("-->", start + 4, true)
            if not finish or input:sub(start + 4, finish - 1):find("--", 1, true) then error("invalid comment") end
            position = finish + 3
        elseif input:sub(start, start + 8) == "<![CDATA[" then
            if #stack == 0 then error("invalid CDATA") end
            local finish = input:find("]]>", start + 9, true)
            if not finish then error("invalid CDATA") end
            append(input:sub(start + 9, finish - 1), true)
            position = finish + 3
        elseif input:sub(start, start + 1) == "<?" then
            local finish = input:find("?>", start + 2, true)
            if not finish or root or not input:sub(start + 2, finish - 1):match("^xml%s") then error("invalid declaration") end
            position = finish + 2
        elseif input:sub(start, start + 1) == "<!" then
            error("unsupported declaration")
        elseif input:sub(start, start + 1) == "</" then
            local finish = input:find(">", start + 2, true)
            local name = finish and input:sub(start + 2, finish - 1):match("^([^%s]+)%s*$")
            if not name or not stack[#stack] or stack[#stack].name ~= name then error("unmatched close") end
            table.remove(stack)
            position = finish + 1
        else
            local cursor = start + 1
            local name = input:match("^([%a_][%w_.:-]*)", cursor)
            if not name or not validName(name) then error("invalid name") end
            cursor = cursor + #name
            local attrs, attrCount, empty = {}, 0, false
            while true do
                local whitespace = input:match("^%s*", cursor)
                cursor = cursor + #whitespace
                local suffix = input:sub(cursor, cursor + 1)
                if suffix == "/>" then empty = true; cursor = cursor + 2; break end
                if input:sub(cursor, cursor) == ">" then cursor = cursor + 1; break end
                if #whitespace == 0 then error("invalid attribute") end
                local key = input:match("^([%a_][%w_.:-]*)", cursor)
                if not key or not validName(key) or attrs[key] ~= nil then error("invalid attribute") end
                cursor = cursor + #key
                local space = input:match("^%s*", cursor); cursor = cursor + #space
                if input:sub(cursor, cursor) ~= "=" then error("invalid attribute") end
                cursor = cursor + 1; space = input:match("^%s*", cursor); cursor = cursor + #space
                local quote = input:sub(cursor, cursor)
                if quote ~= '"' and quote ~= "'" then error("invalid attribute") end
                local finish = input:find(quote, cursor + 1, true)
                if not finish then error("invalid attribute") end
                local value = input:sub(cursor + 1, finish - 1)
                if value:find("<", 1, true) then error("invalid attribute") end
                attrs[key] = decode(value)
                attrCount = attrCount + 1
                if attrCount > 64 then error("too many attributes") end
                cursor = finish + 1
            end
            count = count + 1
            if count > 4096 or #stack >= 32 then error("XML too complex") end
            local parent = stack[#stack]
            local namespaces = { xml = "http://www.w3.org/XML/1998/namespace" }
            if parent then for key, value in pairs(parent.namespaces) do namespaces[key] = value end end
            for key, value in pairs(attrs) do
                if key == "xmlns" then namespaces[""] = value
                else
                    local prefix = key:match("^xmlns:(.+)$")
                    if prefix then
                        if value == "" or prefix == "xmlns" or (prefix == "xml" and value ~= "http://www.w3.org/XML/1998/namespace") then error("invalid namespace") end
                        namespaces[prefix] = value
                    end
                end
            end
            local expanded = {}
            for key in pairs(attrs) do
                local attrPrefix = key:match("^([^:]+):")
                if attrPrefix and attrPrefix ~= "xmlns" and not namespaces[attrPrefix] then error("unknown namespace") end
                if key ~= "xmlns" and attrPrefix ~= "xmlns" then
                    local localKey = attrPrefix and key:sub(#attrPrefix + 2) or key
                    local unique = (attrPrefix and namespaces[attrPrefix] or "") .. "\0" .. localKey
                    if expanded[unique] then error("duplicate attribute") end
                    expanded[unique] = true
                end
            end
            local prefix, localName = name:match("^([^:]+):([^:]+)$")
            if not localName then prefix, localName = "", name end
            if prefix ~= "" and not namespaces[prefix] then error("unknown namespace") end
            local node = { name = name, localName = localName, namespace = namespaces[prefix] or "", attrs = attrs, children = {}, text = "", namespaces = namespaces }
            if parent then table.insert(parent.children, node)
            elseif root then error("multiple roots") else root = node end
            if not empty then table.insert(stack, node) end
            position = cursor
        end
    end
    if #stack ~= 0 or not root then error("incomplete XML") end
    return root
end

return {
    parse = function(input)
        local ok, result = pcall(parseDocument, input)
        if ok then return result end
        return nil, "invalid XML"
    end,
}
