
local function plainFind(str, pat)
	return string.find(str, pat, 0, true)
end

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

local function clamp(n, n1, n2)
	if n < n1 then return n1 end
	if n > n2 then return n2 end
	return n
end

local function readNoSeek(handle, len)
	local dat = handle:read(len)
	handle:seek("cur", -len or 1)
	return dat
end

local lz4 = {}

function lz4.compress(fileHandle)
	local blocks = {}
	local len = fileHandle:seek("end")
	fileHandle:seek("set")
	if len > 8 then
		local firstFour = fileHandle:read(4)
		
		local processed = firstFour
		local lit = firstFour
		local match = ""
		local LiteralPushValue = ""
		local pushToLiteral = true
		
		repeat
			pushToLiteral = true
			local nextByte = fileHandle:read()
			
			if plainFind(processed, nextByte) then
				local next3 = readNoSeek(fileHandle, 3)
				if string.len(next3) < 3 then
					--push bytes to literal block then break
					LiteralPushValue = nextByte .. next3
					fileHandle:seek("cur", 3)
				else
					match = nextByte .. next3
					
					local matchPos = plainFind(processed, match)
					if matchPos then
						fileHandle:seek("cur", 3)
						repeat
							local nextMatchByte = readNoSeek(fileHandle)
							local newResult = match .. nextMatchByte
							
							local repos = plainFind(processed, newResult) 
							if repos then
								match = newResult
								matchPos = repos
								fileHandle:seek("cur", 1)
							end
						until not plainFind(processed, newResult) or fileHandle:seek() == len
						
						local matchLen = string.len(match)
						local pushMatch = true
						if fileHandle:seek() == len then
							if matchLen <= 4 then
								LiteralPushValue = match
								pushMatch = false
							else
								matchLen = matchLen - 4
								match = string.sub(match, 1, matchLen)
								print(match)
								fileHandle:seek("cur", -4)
							end
						end
						
						if pushMatch then
							pushToLiteral = false
							
							-- gets the position from the end of processed, then slaps it onto processed
							local realPosition = string.len(processed) - matchPos
							processed = processed .. match

							table.insert(blocks, {
								Literal = lit,
								LiteralLength = string.len(lit),
								MatchOffset = realPosition + 1,
								MatchLength = matchLen,
							})
							lit = ""
						end
					else
						LiteralPushValue = nextByte
					end
				end
			else
				LiteralPushValue = nextByte
			end
			
			if pushToLiteral then
				lit = lit .. LiteralPushValue
				processed = processed .. nextByte
			end
		until fileHandle:seek() == len
		table.insert(blocks, {
			Literal = lit,
			LiteralLength = string.len(lit)
		})
	else
		local str = fileHandle:read("*a")
		blocks[1] = {
			Literal = str,
			LiteralLength = string.len(str)
		}
	end
	
	-- generate the output chunk
	-- %s is for adding header
	local output = string.rep("\x00", 4)
	local function write(char)
		output = output .. char
	end
	-- begin working through chunks
	for chunkNum, chunk in blocks do
		local litLen = chunk.LiteralLength
		local matLen = (chunk.MatchLength or 4) - 4
		
		-- create token
		local tokenLit = clamp(litLen, 0, 15)
		local tokenMat = clamp(matLen, 0, 15)
		
		local token = (tokenLit << 4) + tokenMat
		write(string.pack("<I1", token))
		
		if litLen >= 15 then
			litLen = litLen - 15
			--begin packing extra bytes
			repeat
				local nextToken = litLen % 256
				write(string.pack("<I1", nextToken))
				if nextToken == 0xFF then
					litLen = litLen - 255
				end
			until nextToken < 0xFF
		end
		
		-- push raw lit data
		write(chunk.Literal)
		
		if chunkNum ~= #blocks then
			-- push offset as u16
			write(string.pack("<I2", chunk.MatchOffset))
		
			-- pack extra match bytes
			if matLen >= 15 then
				matLen = matLen - 15
				
				repeat
					local nextToken = matLen % 256
					write(string.pack("<I1", nextToken))
					if nextToken == 0xFF then
						matLen = matLen - 255
					end
				until nextToken < 0xFF
			end
		end
	end
	--append chunks
	local compLen = string.len(output) - 4
	local decompLen = len
	
	return string.pack("<I4", compLen) .. string.pack("<I4", decompLen) .. output
end
--shut up im testing

local d = hex(lz4.compress("\x01\x00\x00\x00\x04\x00\x00\x00\x4e\x61\x6d\x65\x01\x04\x00\x00\x00\x72\x62\x78\x6d\x06\x00\x00\x00\x53\x74\x72\x69\x6e\x67\x04\x00\x00\x00\x42\x6f\x6f\x6c\x05\x00\x00\x00\x49\x6e\x74\x33\x32\x07\x00\x00\x00\x46\x6c\x6f\x61\x74\x33\x32\x05\x00\x00\x00\x43\x68\x75\x6e\x6b\x0d\x00\x00\x00\x42\x69\x6e\x61\x72\x79\x54\x79\x70\x65\x4d\x61\x70\x0a\x00\x00\x00\x41\x74\x74\x72\x69\x62\x75\x74\x65\x73\x05\x00\x00\x00\x54\x79\x70\x65\x73\x10\x00\x00\x00\x42\x79\x74\x65\x49\x6e\x74\x65\x72\x6c\x65\x61\x76\x69\x6e\x67"))
print(d)