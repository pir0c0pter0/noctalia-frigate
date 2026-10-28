-- Run from the repository root: lua tests/onvif_xml.lua
local xml = assert(loadfile("OnvifXml.luau"))()
local doc = [[<?xml version="1.0"?><s:Envelope xmlns:s="urn:soap" xmlns:w="urn:notification" xmlns:t="urn:types"><s:Body><w:NotificationMessage><w:Topic>tns1:RuleEngine/MyRuleDetector/Visitor</w:Topic><t:Message PropertyOperation="Changed"><t:Data><t:SimpleItem Name="State" Value="true"/></t:Data></t:Message></w:NotificationMessage><w:NotificationMessage><w:Topic>other</w:Topic></w:NotificationMessage></s:Body></s:Envelope>]]
local root = assert(xml.parse(doc))
assert(xml.parse(string.char(239, 187, 191) .. doc).name == "s:Envelope")
assert(root.name == "s:Envelope" and root.namespace == "urn:soap")
local messages = root.children[1].children
assert(#messages == 2 and messages[1].namespace == "urn:notification")
assert(messages[1].children[1].text == "tns1:RuleEngine/MyRuleDetector/Visitor")
local event = messages[1].children[2]
assert(event.attrs.PropertyOperation == "Changed" and event.children[1].children[1].attrs.Value == "true")
local escaped = assert(xml.parse([=[<a xmlns="urn:a" v="&quot;&amp;&#65;&#x42;">left &lt;<![CDATA[raw & text]]></a>]=]))
assert(escaped.namespace == "urn:a" and escaped.attrs.v == '"&AB' and escaped.text == "left <raw & text")
for _, input in ipairs({
    '<!DOCTYPE a [<!ENTITY x "x">]><a>&x;</a>', '<a>&unknown;</a>', '<a><b></a>',
    '<a x="1" x="2"/>', '<x:a/>', '<a x:b="1"/>', '<a xmlns:x=""><x:b/></a>',
    '<a xmlns:xml="urn:wrong"/>', '<a/><b/>', '<a>&#0;</a>', '<a>' .. string.rep('x', 262145) .. '</a>',
    '<a></ a>', '<a>' .. string.char(255) .. '</a>',
    '<a xmlns:x="urn:x" xmlns:y="urn:x" x:v="1" y:v="2"/>',
}) do assert(xml.parse(input) == nil) end
print("ONVIF XML parsing and rejection checks passed")
