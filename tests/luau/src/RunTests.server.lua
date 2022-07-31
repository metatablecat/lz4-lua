local ServerScriptService = game:GetService("ServerScriptService")
local lz4 = require(ServerScriptService.lz4)

local function hex(str)
	local out = ""
	for i = 1, string.len(str) do
		local c = string.sub(str, i, i)
		local b = string.byte(c)
		local padding = "" if b < 0x10 then padding = "0" end

		out = out .. padding .. string.format("%x ", b)
	end

	return out
end

local Tests = {
	["decompression works"] = function()
		local lz4_compressed_data = "\x7d\x00\x00\x00\x80\x00\x00\x00\x00\x00\x00\x00\xd0\x01\x00\x00\x00\x04\x00\x00\x00\x4e\x61\x6d\x65\x01\x09\x00\xe0\x72\x62\x78\x6d\x06\x00\x00\x00\x53\x74\x72\x69\x6e\x67\x1b\x00\xf0\x09\x42\x6f\x6f\x6c\x05\x00\x00\x00\x49\x6e\x74\x33\x32\x07\x00\x00\x00\x46\x6c\x6f\x61\x74\x33\x32\x14\x00\x60\x43\x68\x75\x6e\x6b\x0d\x25\x00\xf0\x0b\x69\x6e\x61\x72\x79\x54\x79\x70\x65\x4d\x61\x70\x0a\x00\x00\x00\x41\x74\x74\x72\x69\x62\x75\x74\x65\x73\x3c\x00\x00\x19\x00\x20\x73\x10\x4d\x00\xf0\x00\x79\x74\x65\x49\x6e\x74\x65\x72\x6c\x65\x61\x76\x69\x6e\x67"
		local expected_data = "\x01\x00\x00\x00\x04\x00\x00\x00\x4e\x61\x6d\x65\x01\x04\x00\x00\x00\x72\x62\x78\x6d\x06\x00\x00\x00\x53\x74\x72\x69\x6e\x67\x04\x00\x00\x00\x42\x6f\x6f\x6c\x05\x00\x00\x00\x49\x6e\x74\x33\x32\x07\x00\x00\x00\x46\x6c\x6f\x61\x74\x33\x32\x05\x00\x00\x00\x43\x68\x75\x6e\x6b\x0d\x00\x00\x00\x42\x69\x6e\x61\x72\x79\x54\x79\x70\x65\x4d\x61\x70\x0a\x00\x00\x00\x41\x74\x74\x72\x69\x62\x75\x74\x65\x73\x05\x00\x00\x00\x54\x79\x70\x65\x73\x10\x00\x00\x00\x42\x79\x74\x65\x49\x6e\x74\x65\x72\x6c\x65\x61\x76\x69\x6e\x67"

		return lz4.decompress(lz4_compressed_data) == expected_data
	end,
	
	["compressed data can be decompressed"] = function()
		local data_chunk = "The LZ4 algorithms aims to provide a good trade-off between speed and compression ratio. Typically, it has a smaller (i.e., worse) compression ratio than the similar LZO algorithm, which in turn is worse than algorithms like DEFLATE. However, LZ4 compression speed is similar to LZO and several times faster than DEFLATE, while decompression speed is significantly faster than LZO"
		local c = lz4.compress(data_chunk)
		return lz4.decompress(c) == data_chunk
	end,

	["arbitrarily large data"] = function()
		-- this test fails, please help fix this

		local data = ""
		for i = 1, 512 do
			local char = string.char(math.random(65,90))
			data ..= string.rep(char, 8)
		end

		local c = lz4.compress(data)
		local d = lz4.decompress(c)

		print(hex(c))
		print(hex(d))
		return lz4.decompress(c) == data
	end
}

for test, call in Tests do
	local worked, testDidWork = pcall(call)
	if not worked then
		print(test, "ERRORED", testDidWork)
	else
		print(test, testDidWork)
	end
end