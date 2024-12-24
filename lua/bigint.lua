--超长整数
local BigInt = class "BigInt"

local CHUNK_SIZE = 3
local BASE = 1000
local BigIntBase = {
	__lt = function (a, b)
		local al, bl = #a, #b
		if al == bl then
			local i = al
			while i > 0 do
				local x, y = tonumber(a[i] or 0), tonumber(b[i] or 0)
				if x < y then
					return true
				elseif x > y then
					return false
				else
					i = i - 1
				end
			end
			return false
		else
			return al < bl
		end
	end,
	__le = function (a, b)
		local al, bl = #a, #b
		if al == bl then
			local i = al
			while i > 0 do
				local x, y = tonumber(a[i] or 0), tonumber(b[i] or 0)
				if x < y then
					return true
				elseif x > y then
					return false
				else
					i = i - 1
				end
			end
			return true
		else
			return al < bl
		end
	end,
	__eq = function (a, b)
		local al, bl = #a, #b
		if al == bl then
			local i = al
			while i > 0 do
				local x, y = tonumber(a[i] or 0), tonumber(b[i] or 0)
				if x == y then
					i = i - 1
				else
					return false
				end
			end
			return true
		else
			return false
		end
	end
}

function BigInt:ctor(value, positive)
	if type(value) == "string" then
		self:_splitNumStr(value)
	elseif type(value) == "table" then
		self:init(value, positive)
	else
		self.m_is_nan = true
	end

	local mt = getmetatable(self)
	mt.__add = function(a, b)
		return a:add(b)
	end
	mt.__sub = function(a, b)
		return a:sub(b)
	end
	mt.__mul = function(a, b)
		return a:mul(b)
	end
	mt.__div = function(a, b)
		return a:div(b)
	end
	mt.__tostring = function(v)
		return v:str()
	end
	setmetatable(self, mt)
end

function BigInt:_splitNumStr(s)
	self.m_num_tab = self:_initTab()
	-- 检查字符串的第一个字符是否为'-'
	s, self.m_positive_flag = self:_checkPositive(s)
	-- 检查首位不为0
	s = self:_checkFirstZero(s)
	if s == "" then return end

	self.m_num_tab = self:_initTab()
	local length = #s
	local end_index = length

	local haveBorrow = false
	while end_index > 0 do
		local start_index = math.max(end_index - CHUNK_SIZE + 1, 1)
		local part = s:sub(start_index, end_index)
		table.insert(self.m_num_tab, part)
		end_index = start_index - 1
	end
end

-- 检查字符串的第一个字符是否为'-'
function BigInt:_checkPositive(s)
	local flag = true
	if s:sub(1, 1) == "-" then
		s = s:sub(2)
		flag = false
	end
	return s, flag
end

-- 检查首位不为0
function BigInt:_checkFirstZero(s)
	local i = 1
	while i <= s:len() and s:sub(i, i) == "0" do
		i = i + 1
	end
	s = s:sub(i)
	return s
end

function BigInt:_initTab()
	local t = {}
	setmetatable(t, BigIntBase)
	return t
end

function BigInt:init(value, positive)
	self.m_num_tab = value
	self.m_positive_flag = positive
	self.m_is_nan = nil
end

function BigInt:getNumData()
	return table.clone(self.m_num_tab)
end

function BigInt:getPositive()
	return self.m_positive_flag
end

function BigInt:str()
	if self.m_is_nan then return "NaN" end
	if #self.m_num_tab == 0 then return "0" end

	local str = ""
	for i = #self.m_num_tab, 1, -1 do
		str = str..self.m_num_tab[i]
	end
	if not self.m_positive_flag then
		str = "-"..str
	end
	return str
end

function BigInt:setZero()
	self.m_num_tab = self:_initTab()
	self.m_positive_flag = true
	self.m_is_nan = nil
end

function BigInt:isZero()
	return #self.m_num_tab == 0
end

function BigInt:setNaN()
	self.m_is_nan = true
	self.m_num_tab = nil
	self.m_positive_flag = nil
end

function BigInt:isNaN()
	return self.m_is_nan
end

function BigInt:add(target)
	local result = BigInt.new()

	if self:isNaN() or target:isNaN() then
		error("number is NaN")
	elseif self:isZero() then
		result:init(target:getNumData(), target:getPositive())
	elseif target:isZero() then
		result:init(self:getNumData(), self:getPositive())
	else
		local a, b = self:getNumData(), target:getNumData()
		local af, bf = self:getPositive(), target:getPositive()
		--同号相加，异号相减，符号取大的
		if af ~= bf then
			if a > b then
				result:init(self:_sub(a, b), af)
			elseif a < b then
				result:init(self:_sub(b, a), bf)
			else
				result:setZero()
			end
		else
			result:init(self:_add(a, b), af)
		end
	end

	return result
end

function BigInt:_add(a, b)
	local result = self:_initTab()

	local temp = 0
	local length = math.max(#a, #b)
	for i = 1, length do
		local x = tonumber(a[i] or 0) + tonumber(b[i] or 0) + temp
		local s = tostring(x)
		local end_index = #s
		local start_index = math.max(end_index - CHUNK_SIZE + 1, 1)
		local part = s:sub(start_index, end_index)
		if start_index ~= 1 then
			temp = tonumber(s:sub(1,start_index-1))
		else
			temp = 0
		end
		table.insert(result, part)
	end

	return result
end

function BigInt:sub(target)
	local result = BigInt.new()

	if self:isNaN() or target:isNaN() then
		error("number is NaN")
	elseif self:isZero() then
		result:init(target:getNumData(), (not target:getPositive()))
	elseif target:isZero() then
		result:init(self:getNumData(), self:getPositive())
	else
		local a, b = self:getNumData(), target:getNumData()
		local af, bf = self:getPositive(), target:getPositive()
		if af and bf then
			if a > b then
				result:init(self:_sub(a, b), true)
			elseif a < b then
				result:init(self:_sub(b, a), false)
			else
				result:setZero()
			end
		elseif not af and not bf then
			if a > b then
				result:init(self:_sub(a, b), false)
			elseif a < b then
				result:init(self:_sub(b, a), true)
			else
				result:setZero()
			end
		elseif (af and not bf) or (not af and bf) then
			result:init(self:_add(a, b), af)
		end
	end

	return result
end

function BigInt:_sub(a, b)
	local result = self:_initTab()

	local temp = 0
	local length = math.max(#a, #b)
	for i = 1, length do
		--直接借位不管那么多
		if a[i+1] then
			a[i] = "1"..a[i]
		end
		local x = tonumber(a[i] or 0) - tonumber(b[i] or 0) + temp
		local s = tostring(x)
		local end_index = #s
		local start_index = math.max(end_index - CHUNK_SIZE + 1, 1)
		local part = s:sub(start_index, end_index)
		--如果借位的多了就不管，用了就扣掉
		if start_index ~= 1 then
			temp = 0
		else
			temp = -1
		end
		table.insert(result, part)
	end

	--去零
	local i = #result
	while i > 0 do
		local s = self:_checkFirstZero(result[i])
		if s == "" then
			table.remove(result, i)
			i = i - 1
		else
			result[i] = s
			break
		end
	end

	return result
end

function BigInt:mul(target)
	local result = BigInt.new()

	if self:isNaN() or target:isNaN() then
		error("number is NaN")
	elseif self:isZero() or target:isZero() then
		result:setZero()
	else
		local a, b = self:getNumData(), target:getNumData()
		local af, bf = self:getPositive(), target:getPositive()
		if af == bf then
			result:init(self:_mul(a, b), true)
		else
			result:init(self:_mul(a, b), false)
		end
	end

	return result
end

function BigInt:_mul(a, b)
	local result = self:_initTab()

	local xL, yL = #a, #b
	if xL < yL then
		a, b = b, a
		xL, yL = yL, xL
	end
	local r = {}
	for i = 1, yL do
		local carry = 0
		local j = i
		for k = 1, xL do
			local x = (r[j] or 0) + tonumber(b[i]) * tonumber(a[k]) + carry
			r[j] = math.floor(x % BASE)
			carry = math.floor(x / BASE)
			j = j + 1
		end
		r[j] = ((r[j] or 0) + carry) % BASE
	end

	local i = #r
	while i > 0 do
		--去零
		if not (not result[1] and r[i] == 0) then
			local s = tostring(r[i])
			--补零
			if result[1] then
				local t = CHUNK_SIZE - #s
				if t > 0 then
					for j = 1, t do s = "0"..s end
				end
			end
			table.insert(result, 1, s)
		end
		i = i - 1
	end

	return result
end

function BigInt:div(target)
	local result = BigInt.new()

	if self:isNaN() or target:isNaN() then
		error("number is NaN")
	elseif self:isZero() then
		result:setZero()
	elseif target:isZero() then
		result:setNaN()
	else
		local a, b = self:getNumData(), target:getNumData()
		local af, bf = self:getPositive(), target:getPositive()
		if af == bf then
			result:init(self:_div(a, b), true)
		else
			result:init(self:_div(a, b), false)
		end
	end

	return result
end

function BigInt:_div(a, b)
	local result = self:_initTab()
	if a < b then
		table.insert(result, "0")
		return result
	elseif a == b then
		table.insert(result, "1")
		return result
	end

	local r = {}
	local xL, yL = #a, #b
	-- printx(self:_getEPoint(a), self:_getEPoint(b))
	-- local e = math.floor(self:_getEPoint(a) / CHUNK_SIZE) - math.floor(self:_getEPoint(b) / CHUNK_SIZE)
	if yL == 1 then
		local carry = 0;
		local y = tonumber(b[1]);
		local i = xL
		while i > 0 do
			local x = carry * BASE + tonumber(a[i])
			table.insert(r, 1, math.floor(x / y))
			carry = math.floor(x % y)
			i = i - 1
		end
	else
		local k = math.floor(BASE / (tonumber(b[yL]) + 1))
		local xd, yd = a, b
		if k > 1 then
			yd = self:_multiplyInteger(b, k, BASE);
			xd = self:_multiplyInteger(a, k, BASE);
			yL = #yd;
			xL = #xd;
		end

		local rem = self:_initTab()
		for j = 1, yL do
			if xd[#xd - j + 1] then
				table.insert(rem, 1, xd[#xd - j + 1])
			else
				break
			end
		end
		if #rem < yL then
			table.insert(rem, 1, 0)
		end
		local xi = yL
		local yz = table.clone(yd)
		table.insert(yz, 0)
		local yd0 = yd[#yd]

		if tonumber(yd[#yd - 1]) >= BASE / 2 then
			yd0 = yd0 + 1
		end

		local prod
		repeat
			local k = 0
			local cmp = self:_compare(yd, rem)
			if cmp < 0 then
				local rem0 = rem[#rem]
				if yL ~= #rem then
					rem0 = rem0 * BASE + (rem[#rem - 1] or 0)
				end
				k = math.floor(rem0 / yd0)
				if k > 1 then
					if k >= BASE then
						k = BASE - 1
					end

					prod = self:_multiplyInteger(yd, k, BASE)

					cmp = self:_compare(prod, rem)
					if cmp == 1 then
						k = k - 1
						self:_subtract(prod, yL < (#prod) and yz or yd)
					end
				else
					if k == 0 then
						cmp = 1
						k = 1
					end
					prod = table.clone(yd)
				end

				if #prod < #rem then
					table.insert(prod, 0)
				end

				self:_subtract(rem, prod)

				if cmp == -1 then
					cmp = self:_compare(yd, rem, yL, #rem)

					if cmp < 1 then
						k = k + 1
						self:_subtract(rem, yL < (#rem) and yz or yd)
					end
				end
			elseif cmp == 0 then
				k = k+1
				rem = self:_initTab()
				table.insert(rem, 0)
			end

			table.insert(r, 1, k)

			if (cmp ~= 0 and tonumber(rem[#rem]) > 0) then
				table.insert(rem, 1, (xd[#xd - xi] or 0))
			else
				rem = self:_initTab()
				table.insert(rem, xd[#xd - xi] or 0)
			end

			xi = xi + 1
		until (xi > xL or rem[#rem] == 0)
	end

	-- --去零
	-- while r[#r] == 0 do
	-- 	table.remove(r)
	-- end
	-- --仅保留整数部分
	-- local i = 1
	-- local k = r[#r] or 0
	-- while k >= 10 do
	-- 	k = k / 10
	-- 	i = i + 1
	-- end
	-- e = i + e * CHUNK_SIZE - 1
	-- printx("===========", e)

	local i = #r
	while i > 0 do
		if not (not result[1] and r[i] == 0) then
			local s = tostring(r[i])
			--补零
			if result[1] then
				local t = CHUNK_SIZE - #s
				if t > 0 then
					for j = 1, t do s = "0"..s end
				end
			end
			table.insert(result, 1, s)
		end
		i = i - 1
	end

	return result
end

function BigInt:_multiplyInteger(x, k)
	local temp
	local carry = 0
	x = table.clone(x)
	for i = 1, #x do
		temp = x[i] * k + carry
		x[i] = math.floor(temp % BASE)
		carry = math.floor(temp / BASE)
	end

	if carry > 0 then
		table.insert(x, carry)
	end

	return x
end

function BigInt:_compare(a, b)
	if a > b then
		return 1
	elseif a < b then
		return -1
	else
		return 0
	end
end

function BigInt:_subtract(a, b)
	local xL, yL = #a, #b
	local k = 0;
	for i = 1, xL do
		a[i] = tonumber(a[i]) - k
		k = tonumber(a[i]) < tonumber(b[i]) and 1 or 0
		a[i] = k * BASE + tonumber(a[i]) - tonumber(b[i])
	end

	while a[#a] == 0 do
		table.remove(a)
	end
end

-- function BigInt:_getEPoint(a)
-- 	return #(tostring(a[#a])) + (#a-1) * CHUNK_SIZE - 1
-- end

return BigInt
