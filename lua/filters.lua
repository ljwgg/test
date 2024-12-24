--屏蔽字库
local Filters = class "Filters"

function Filters:ctor()
	self.m_filter_tree = self:_newFilterData()
end

function Filters:_newFilterData()
	return {isEnd = false, children = {}}
end

function Filters:_addFilter(children, input)
	local len = string.len(input)
	local symbol = string.sub(input, 1, 1)
	if not children[symbol] then
		children[symbol] = self:_newFilterData()
	end
	if len > 1 then
		local last = string.sub(input, 2)
		self:addFilter(children[symbol].children, last)
	else
		children[symbol].isEnd = true
	end
end

--添加屏蔽字
function Filters:addFilter(input)
	if type(input) ~= "string" then return end
	local len = string.len(input)
	if len == 0 then return end

	self:_addFilter(self.m_filter_tree.children, input)
end

--检查屏蔽字
function Filters:checkFilterWords(input)
	if type(input) ~= "string" then return false end
	local len = string.len(input)
	if len == 0 then return false end
	local current = self.m_filter_tree
	local i = 1
	local temp = ""
	while i < len do
		local symbol = string.sub(input, i, i+1)
		local s = string.lower(symbol)
		local filterData = current[s]
		if filterData then
			temp = temp..symbol
			if filterData.isEnd then
				return true
			else
				current = filterData.children
			end
		else
			current = self.m_filter_tree
			temp = ""
		end
		i = i + 1
	end

	return false
end

--检查并替换屏蔽字
function Filters:filterWords(input)
	if type(input) ~= "string" then return input end
	local len = string.len(input)
	if len == 0 then return input end
	local current = self.m_filter_tree
	local i = 1
	local tab = {}
	local temp = ""
	while i < len do
		local symbol = string.sub(input, i, i+1)
		local s = string.lower(symbol)
		local filterData = current[s]
		if filterData then
			temp = temp..symbol
			if filterData.isEnd then
				table.insert(tab, temp)
				temp = ""
			else
				current = filterData.children
			end
		else
			current = self.m_filter_tree
			temp = ""
		end
		i = i + 1
	end

	local output = input
	for i, v in ipairs(tab) do
		local len = string.len(v)
		local s = ""
		for j = 1, len do s = s.."*" end
		output = string.gsub(output, v, s)
	end

	return output
end

return Filters
