-- metatablecat 2022

local lz4 = {}

local function plainFind(str, pat)
	return string.find(str, pat, 0, true)
end

local function clamp(n, n1, n2)
	if n < n1 then return n1 end
	if n > n2 then return n2 end
	return n
end

local function streamer(str)
	local Stream = {}
	Stream.Offset = 0
	Stream.Source = str
	Stream.Length = string.len(str)
	Stream.IsFinished = false	
	
	function Stream:read(len, shift)
		local len = len or 1
		if shift == nil then shift = true else shift = shift end

		local dat = string.sub(self.Source, self.Offset + 1, self.Offset + len)
		
		if shift then
			self:seek(len)
		end
		
		return dat
	end
	
	function Stream:seek(len)
		local len = len or 1
		
		self.Offset = clamp(self.Offset + len, 0, self.Length)
		self.IsFinished = self.Offset >= self.Length
	end
	
	return Stream
end

function lz4.compress(str)
	local blocks = {}
	local iostream = streamer(str)
	
	if iostream.Length > 8 then
		local firstFour = iostream:read(4)

		local processed = firstFour
		local lit = firstFour
		local match = ""
		local LiteralPushValue = ""
		local pushToLiteral = true
		
		repeat
			pushToLiteral = true
			local nextByte = iostream:read()

			if plainFind(processed, nextByte) then
				local next3 = iostream:read(3, false)
				
				if string.len(next3) < 3 then
					--push bytes to literal block then break
					LiteralPushValue = nextByte .. next3
					iostream:seek(3)
				else
					match = nextByte .. next3

					local matchPos = plainFind(processed, match)
					if matchPos then
						iostream:seek(3)
						repeat
							local nextMatchByte = iostream:read(1, false)
							local newResult = match .. nextMatchByte

							local repos = plainFind(processed, newResult) 
							if repos then
								match = newResult
								matchPos = repos
								iostream:seek(1)
							end
						until not plainFind(processed, newResult) or iostream.IsFinished

						local matchLen = string.len(match)
						local pushMatch = true
						
						if iostream.IsFinished then
							if matchLen <= 4 then
								LiteralPushValue = match
								pushMatch = false
							else
								matchLen = matchLen - 4
								match = string.sub(match, 1, matchLen)
								iostream:seek(-4)
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
		until iostream.IsFinished
		table.insert(blocks, {
			Literal = lit,
			LiteralLength = string.len(lit)
		})
	else
		local str = iostream.Source
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
	for chunkNum, chunk in ipairs(blocks) do
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
				local nextToken = clamp(litLen, 0, 0xFF)
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
					local nextToken = clamp(matLen, 0, 0xFF)
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
	local decompLen = iostream.Length

	return string.pack("<I4", compLen) .. string.pack("<I4", decompLen) .. output
end

function lz4.decompress(lz4data)
	local iostream = streamer(lz4data)
	local compressedLen = string.unpack("<I4", iostream:read(4))
	local decompressedLen = string.unpack("<I4", iostream:read(4))
	local reserved = string.unpack("<I4", iostream:read(4))
	
	if compressedLen == 0 then
		return iostream:read(iostream.Length)
	end
	
	local outBuffer = ""
	repeat
		local token = string.byte(iostream:read())
		local litLen = token >> 4
		local matLen = token & 0xF
		
		if litLen == 15 then
			repeat
				local nextByte = string.byte(iostream:read())
				litLen = litLen + nextByte
			until nextByte ~= 0xFF
		end

		outBuffer = outBuffer .. iostream:read(litLen)
		
		if not iostream.IsFinished then
			local offset = string.unpack("<I2", iostream:read(2))
			if matLen == 15 then
				repeat
					local nextByte = string.byte(iostream:read())
					matLen = matLen + nextByte
				until nextByte ~= 0xFF
			end
			matLen = matLen + 3
			local off = (string.len(outBuffer) - offset) + 1
			local offsetData = string.sub(outBuffer, off, off + matLen)
			outBuffer = outBuffer .. offsetData
		end
	until iostream.IsFinished
	
	return outBuffer
end

return lz4
