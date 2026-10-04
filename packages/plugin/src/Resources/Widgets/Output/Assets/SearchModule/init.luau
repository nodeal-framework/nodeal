--!nonstrict
local searchbar = {}
--[[
local utilFunctions = {}

function utilFunctions.getChildrenOfClass(instance : Instance, class : string)
	local children = instance:GetChildren()
	local sorted = {}
	for i = 1,#children,0 do
		if(children[i]:IsA(class)) then
			table.insert(sorted, children[i])
		end
	end
	return sorted
end
function utilFunctions.getTableObjectsComponentsOfClass(tab, class : string)
	local sorted = {}
	for i = 1,#tab,0 do
		if(tab[i]:IsA(class)) then
			table.insert(sorted, tab[i])
		end
	end
	return sorted
end
]]
function searchbar:GetSortedListFromStringTable(tab, input : string, typosConsidered : boolean, capsConsidered : boolean, ignoreNoMatches : boolean)
	local sortedInput = input
	if(not capsConsidered) then
		sortedInput = sortedInput:lower()
	end

	local terms = sortedInput:split(" ")
	local arrangement = {}

	for i = 1,#tab,1 do --Iterate through the sentences
		local _firstLetter : string, _lastLetter : string --Saving the last letters found
		local originalString = tab[i]
		
		local modifiedString = originalString
		if not capsConsidered then modifiedString = modifiedString:lower() end
		local currentString = modifiedString

		local score = 0
		local smallest = true --The string is currently considered the smallest in the table, but soon score will be added to it.
		for j = 1,#terms,1 do
			if(not capsConsidered) then terms[j] = terms[j]:lower() end
			local term = terms[j]
			local found = false
			local firstLetter, lastLetter = string.find(modifiedString, term)
			--print(firstLetter, originalString, term)
			for _, word in pairs(modifiedString:split(" ")) do
				if(word == term) then --Check if the word is equal to one of the words in the string
					if(string.len(word) > 1) then
						if not capsConsidered then word = word:lower() end
						--print(word, term)
						score+=3
						--print("score given" .. term)
						_firstLetter = firstLetter
						_lastLetter = lastLetter
						found = true
						break
					else
						score+=1.5
						--print("score given" .. term)
						found = true
						break
					end
				end
			end
			if found == false then
				if(firstLetter and lastLetter) then
					--print(firstLetter)
					if(_lastLetter) then
						if(_lastLetter > firstLetter) then --If the current word is AFTER the last word, then
							if(string.len(term) > 1) then-- If the word is not something like "I"
								score+=2
								--print("score given" .. term)

								_firstLetter = firstLetter
								_lastLetter = lastLetter
							else
								score+=0.5
								--print("score given" .. term)

							end
							if firstLetter == 1 then
								currentString = currentString:sub(lastLetter+1, #currentString)
							else
								currentString = currentString:sub(1, firstLetter-1) .. currentString:sub(lastLetter+1, #currentString)
							end
						else
							if firstLetter == 1 then
								currentString = currentString:sub(lastLetter+1, #currentString)
							else
								currentString = currentString:sub(1, firstLetter-1) .. currentString:sub(lastLetter+1, #currentString)
							end
						end
					else --Word found but there's no word before it.
						if(string.len(term) > 1) then
							score+=2
							_firstLetter = firstLetter
							_lastLetter = lastLetter
						else --If a word is like "I"
							score+=0.5
							--print("score given" .. term)

						end
						if firstLetter == 1 then
							currentString = currentString:sub(lastLetter+1, #currentString)
						else
							currentString = currentString:sub(1, firstLetter-1) .. currentString:sub(lastLetter+1, #currentString)
						end
					end
				else
					if(typosConsidered) then
						if(string.len(term) > 1) then
							for k = 1,string.len(term),1 do
								local typoTerm
								if k == 1 then
									typoTerm = "." .. terms[j]:sub(2, #terms[j])
								else
									typoTerm = terms[j]:sub(1, k-1) .. "." .. terms[j]:sub(k+1, #terms[j])
								end
								firstLetter, lastLetter = string.find(modifiedString, typoTerm)
								if(firstLetter and lastLetter) then
									if(modifiedString:sub(firstLetter,firstLetter) == " ") then continue end
									if(_lastLetter) then
										if(_lastLetter < firstLetter) then
											score+=1
											--print("found and given")

											currentString = currentString:sub(1, firstLetter-1) .. currentString:sub(lastLetter+1, #currentString)
											_firstLetter = firstLetter
											_lastLetter = lastLetter
											break
										else
											currentString = currentString:sub(1, firstLetter-1) .. currentString:sub(lastLetter+1, #currentString)
										end
									else
										score+=1
										--print("found and given")
										currentString = currentString:sub(1, firstLetter-1) .. currentString:sub(lastLetter+1, #currentString)
										_firstLetter = firstLetter
										_lastLetter = lastLetter
										break
									end
								end
							end
						end
					end
				end
			else
				continue
			end
		end
		if(modifiedString == sortedInput) then
			score = math.huge
		end
		--Arrange the strings by the score each string recieved by the filters.
		if(#arrangement == 0) then
			if(ignoreNoMatches) then
				if(score > 0) then
					table.insert(arrangement, {originalString, score})

				end
			else
				table.insert(arrangement, {originalString, score})
			end
		else
			for j = 1,#arrangement,1 do
				if(ignoreNoMatches) then
					if(score >= 0) then
						break
					end
				end
				if(score > arrangement[j][2]) then
					table.insert(arrangement, j, {originalString, score})
					smallest = false
					break
				elseif(currentString == arrangement[j][2] and #arrangement[j][1] > #originalString) then
					table.insert(arrangement, j-1, {originalString, score})
					smallest = false
					break
				end
			end
			if(smallest) then
				if(ignoreNoMatches and score > 0) then
					table.insert(arrangement, {originalString, score})
				elseif(not ignoreNoMatches) then
					table.insert(arrangement, {originalString, score})
				end
			end
		end
	end
	for i = 1,#arrangement,1 do
		arrangement[i] = arrangement[i][1] --Remove the scores from the table
	end
	return arrangement
end

function searchbar:GetSortedListFromInstanceTable(tab, classFilter : string, propertyFilter : string, input : string, typosConsidered : boolean, capsConsidered : boolean, ignoreNoMatches : boolean)
	local stringTab = {}
	for i = 1,#tab,1 do
		if(tab[i]:IsA(classFilter)) then
			if(tab[i]:GetAttribute(propertyFilter)) then
				local str = tostring(tab[i]:GetAttribute(propertyFilter))
				table.insert(stringTab, str)
			end
		end
	end
	local sortedStrings = searchbar:GetSortedListFromStringTable(stringTab, input, typosConsidered, capsConsidered, ignoreNoMatches)
	--Group by attribute once instead of rescanning the whole table per sorted string. Same order out:
	--the buckets keep the order the instances came in, which is what the inner loop walked.
	local buckets = {}
	for j = 1,#tab,1 do
		if(tab[j]:IsA(classFilter)) then
			local property = tostring(tab[j]:GetAttribute(propertyFilter))
			if not capsConsidered then
				property = property:lower()
			end
			local bucket = buckets[property]
			if not bucket then
				bucket = {}
				buckets[property] = bucket
			end
			bucket[#bucket + 1] = tab[j]
		end
	end

	local arrangement = {}
	for i = 1,#sortedStrings,1 do
		local wanted = sortedStrings[i]
		if not capsConsidered then
			wanted = wanted:lower()
		end
		local bucket = buckets[wanted]
		if bucket then
			for _, item in bucket do
				arrangement[#arrangement + 1] = item
			end
		end
	end
	return arrangement
end

function searchbar:GetSortedListFromInstanceChildren(instance : Instance, classFilter : string, propertyFilter : string, input : string, typosConsidered : boolean, capsConsidered : boolean, ignoreNoMatches : boolean)
	if(typeof(instance) == "Instance") then
		local arrangement = searchbar:GetSortedListFromInstanceTable(instance:GetChildren(), classFilter, propertyFilter, input, typosConsidered, capsConsidered, ignoreNoMatches)
		return arrangement
	else
		error("Expected Instance, got " .. (instance.ClassName or type(instance)))
	end
end
return searchbar
