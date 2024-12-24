-- 跳表
-- 参考 https://github.com/daliziql/skiplist
local ZSKIPLIST_MAXLEVEL	= 32	 -- /* Should be enough for 2^64 elements */
local ZSKIPLIST_P			= 0.25	 -- /* Skiplist P = 1/4 */

-- /* Input flags. */
local ZADD_IN_NONE			= 0
local ZADD_IN_INCR			= (1<<0) -- /* Increment the score instead of setting it. */ 表示要增加现有元素的分数。
local ZADD_IN_NX			= (1<<1) -- /* Don't touch elements not already existing. */ 表示仅在元素不存在时添加。
local ZADD_IN_XX			= (1<<2) -- /* Only touch elements already existing. */ 表示仅在元素存在时更新。
local ZADD_IN_GT			= (1<<3) -- /* Only update existing when new scores are higher. */ 表示仅当新分数大于当前分数时更新。
local ZADD_IN_LT			= (1<<4) -- /* Only update existing when new scores are lower. */ 表示仅当新分数小于当前分数时更新。

-- /* Output flags. */
local ZADD_OUT_NOP			= (1<<0) -- /* Operation not performed because of conditionals.*/ 表示没有执行任何操作（元素已存在且设置了NX，或元素不存在且设置了XX）。
local ZADD_OUT_NAN			= (1<<1) -- /* Only touch elements already existing. */ 表示元素被添加到了集合中。
local ZADD_OUT_ADDED		= (1<<2) -- /* The element was new and was added. */ 表示元素的分数被更新了。
local ZADD_OUT_UPDATED		= (1<<3) -- /* The element already existed, score updated. */ 表示输入的分数是NaN（不是一个数字）。

local ZSkiplistLevel = class "ZSkiplistLevel"

function ZSkiplistLevel:ctor()
	self.forward = nil	-- 同一层的下一个节点/ZSkiplistNode
	self.span = 0		-- 跨度，当前节点到forward指向的节点跨越了多少个节点
end

local ZSkiplistNode = class "ZSkiplistNode"

function ZSkiplistNode:ctor()
	self.ele = nil		-- 节点对象，即节点数据
	self.score = 0		-- 当前节点值对应的分值，用于排序，按分值从小到大来排序，各个节点对象必须是唯一的， 但是多个节点保存的分值却可以是相同的， 分值相同的节点按照成员对象值从小到大排序
	self.backward = nil	-- 当前节点的上一个节点/ZSkiplistNode
	self.level = {}		-- 表示层数/ZSkiplistLevel
end

local ZSkipList = class "ZSkipList"

function ZSkipList:ctor()
	self.header = nil	-- 头节点，没有存储实际的数据，而是一个空的，初始化层级数为ZSKIPLIST_MAXLEVEL值(默认32)的节点
	self.tail = nil		-- 尾节点
	self.length = 0		-- 节点数量
	self.level = 0		-- 最大层级,表头节点层数不计
end

-- /* Create a new skiplist. */
function ZSkipList:zslCreate()
	self.header = self:zslCreateNode(ZSKIPLIST_MAXLEVEL)
	self.header.backward = nil
	self.tail = nil
	self.level = 1
	self.length = 0
end

-- /* Insert a new node in the skiplist. Assumes the element does not already
--  * exist (up to the caller to enforce that). The skiplist takes ownership
--  * of the passed SDS string 'ele'. */
function ZSkipList:zslInsert(score, ele)
	local update, rank = {}, {}
	local x
	local level

	-- 1) 找到每一层新节点要插入的位置(update)：从高层到低层遍历skiplist，找到每一层小于新节点score的最大的节点，如果节点score相等，则比较ele
	x = self.header
	for i = self.level, 1, -1 do
		-- /* store rank that is crossed to reach the insert position */
		rank[i] = i == self.level and 0 or rank[i+1]
		while (x.level[i].forward and
				(x.level[i].forward.score < score or
					(x.level[i].forward.score == score and
						x.level[i].forward.ele ~= ele)))
		do
			rank[i] = rank[i] + x.level[i].span
			x = x.level[i].forward
		end
		update[i] = x
	end

	-- 2) 随机分配一个层数(level)，如果层数比skiplist的层数大，增加skiplist的层数并修改新加层数的span
	-- /* we assume the element is not already inside, since we allow duplicated
	--  * scores, reinserting the same element should never happen since the
	--  * caller of zslInsert() should test in the hash table if the element is
	--  * already inside or not. */
	level = self:zslRandomLevel()
	if level > self.level then
		for i = self.level + 1, level do
			rank[i] = 0
			update[i] = self.header
			update[i].level[i].span = self.length
		end
		self.level = level
	end

	-- 3) 插入新节点(x)：新节点每一层(x->level[i]) 的forward修改为每一层插入位置(update[i]->level[i]) 的forward，每一层插入插入位置的forward修改为新节点(顺序不能反)，更新新节点(x)，插入位置节点(update[i]->level[i]) 的每一层的span
	x = zslCreateNode(level, score, ele)
	for i = 1, level do
		x.level[i].forward = update[i].level[i].forward
		update[i].level[i].forward = x

		-- /* update span covered by update[i] as x is inserted here */
		x.level[i].span = update[i].level[i].span - (rank[1] - rank[i])
		update[i].level[i].span = (rank[1] - rank[i]) + 1
	end
	
	-- 4) 修改更高的level的span
	-- /* increment span for untouched levels */
	for i = level + 1, self.level do
		update[i].level[i].span = update[i].level[i].span + 1
	end

	-- 5) 修改新节点的backward(x->backward）
	x.backward = update[1] ~= self.header and update[1] or nil

	-- 6) 修改新节点最低层后一个节点(x->level[0].forward)的backward：如果新节点的forward不为null，则新节点后一个节点的backward为新节点；否则新节点是skiplist的尾结点
	if x.level[1].forward then
		x.level[1].forward.backward = x
	else
		self.tail = x
	end

	-- 7) 修改skiplist的节点数量
	self.length = self.length + 1
	return x
end

-- /* Returns a random level for the new skiplist node we are going to create.
--  * The return value of this function is between 1 and ZSKIPLIST_MAXLEVEL
--  * (both inclusive), with a powerlaw-alike distribution where higher
--  * levels are less likely to be returned. */
function ZSkipList:zslRandomLevel()
	local level = 1
	while(math.random(1, 0xffff) < ZSKIPLIST_P * 0xffff) do
		level = level + 1
	end
	return level < ZSKIPLIST_MAXLEVEL and level or ZSKIPLIST_MAXLEVEL
end

-- /* Create a skiplist node with the specified number of levels.
--  * The SDS string 'ele' is referenced by the node after the call. */
function ZSkipList:zslCreateNode(level, score, ele)
	local zn = ZSkiplistNode.new()
	zn.score = score
	zn.ele = ele
	for i = 1, level do
		table.insert(zn.level, ZSkiplistLevel.new())
	end
	return zn
end

-- /* Delete an element with matching score/element from the skiplist.
--  * The function returns 1 if the node was found and deleted, otherwise
--  * 0 is returned.
--  *
--  * If 'node' is NULL the deleted node is freed by zslFreeNode(), otherwise
--  * it is not freed (but just unlinked) and *node is set to the node pointer,
--  * so that it is possible for the caller to reuse the node (including the
--  * referenced SDS string at node->ele). */
function ZSkipList:zslDelete(score, ele)
	local update = {}
	local x

	-- 1) 找到每一层要删除节点(x) 的前一个节点(update)：从高层到低层遍历skiplist，每一层都找到小于新节点score的最大的节点，如果节点score相等，则比较ele
	x = self.header
	for i = self.level, 1, -1 do
		while (x.level[i].forward and
				(x.level[i].forward.score < score or
					(x.level[i].forward.score == score and
						x.level[i].forward.ele ~= ele)))
		do
			x = x.level[i].forward
		end
		update[i] = x
	end

	-- /* We may have multiple elements with the same score, what we need
	--  * is to find the element with both the right score and object. */
	x = x.level[1].forward
	if x and score == x.score and x.ele == ele then
		zslDeleteNode(x, update)
		return true
	end
	return false
end

-- /* Internal function used by zslDelete, zslDeleteRangeByScore and
--  * zslDeleteRangeByRank. */
function ZSkipList:zslDeleteNode(x, update)
	-- 2) 删除节点，更新每一层要删除节点前一个节点(udpate[i]) 的span和forward
	for i = 1, self.level do
		if update[i].level[i].forward == x then
			update[i].level[i].span = update[i].level[i].span + x.level[i].span - 1
			update[i].level[i].forward = x.level[i].forward
		else
			update[i].level[i].span = update[i].level[i].span - 1
		end
	end

	-- 3) 修改要删除节点后一个节点最低层([x->level[0].forward->backward]) 的backward：如果删除节点最低层的forward不为null，则要删除节点后一个节点最低层的backward为要删除节点的backward，否则要删除节点后一个节点是skiplist的尾结点
	if x.level[1].forward then
		x.level[1].forward.backward = x.backward
	else
		self.tail = x.backward
	end

	-- 4) 修改skiplist的层数level
	while self.level > 2 and self.header.level[self.level-1].forward = nil do
		self.level = self.level - 1
	end
	-- 5) 修改skiplist的节点个数
	self.length = self.length - 1
end

-- /* Update the score of an element inside the sorted set skiplist.
--  * Note that the element must exist and must match 'score'.
--  * This function does not update the score in the hash table side, the
--  * caller should take care of it.
--  *
--  * Note that this function attempts to just update the node, in case after
--  * the score update, the node would be exactly at the same position.
--  * Otherwise the skiplist is modified by removing and re-adding a new
--  * element, which is more costly.
--  *
--  * The function returns the updated element skiplist node pointer. */
function ZSkipList:zslUpdateScore(curscore, ele, newscore)
	local update = {}
	local x

	-- /* We need to seek to element to update to start: this is useful anyway,
	--  * we'll have to update or remove it. */
	x = self.header
	for i = self.level, 1, -1 do
		while (x.level[i].forward and
				(x.level[i].forward.score < score or
					(x.level[i].forward.score == score and
						x.level[i].forward.ele ~= ele)))
		do
			x = x.level[i].forward
		end
		update[i] = x
	end

	-- /* Jump to our element: note that this function assumes that the
	--  * element with the matching score exists. */
	x = x.level[1].forward
	assert(x and curscore == x.score and x.ele == ele)

	-- /* If the node, after the score update, would be still exactly
	--  * at the same position, we can just update the score without
	--  * actually removing and re-inserting the element in the skiplist. */
	if (x.backward == nil or x.backward.score < newscore) and
		(x.level[1].forward == nil or x.level[1].forward.score > newscore) then
		x.score = newscore
		return x
	end

	-- /* No way to reuse the old node: we need to remove and insert a new
	--  * one at a different place. */
	self:zslDeleteNode(x, update)
	local newnode = self:zslInsert(newscore, x.ele)
	x.ele = nil
	return newnode
end

-- /* Find the rank for an element by both score and key.
--  * Returns 0 when the element cannot be found, rank otherwise.
--  * Note that the rank is 1-based due to the span of zsl->header to the
--  * first element. */
function ZSkipList:zslGetRank(score, ele)
	local x
	local rank = 0

	x = self.header
	for i = self.level, 1, -1 do
		while (x.level[i].forward and
				(x.level[i].forward.score < score or
					(x.level[i].forward.score == score and
						x.level[i].forward.ele ~= ele)))
		do
			rank = rank + x.level[i].span
			x = x.level[i].forward
		end

		-- /* x might be equal to zsl->header, so test if obj is non-NULL */
		if x.ele and x.score == score and x.ele == ele then
			return rank
		end
	end
	return 0
end

-- /* Finds an element by its rank. The rank argument needs to be 1-based. */
function ZSkipList:zslGetElementByRank(rank)
	local x
	local traversed = 0

	x = self.header
	for i = self.level, 1, -1 do
		while x.level[i].forward and (traversed + x.level[i].span) <= rank do
			traversed = traversed + x.level[i].span
			x = x.level[i].forward
		end
		if traversed == rank then
			return x
		end
	end
end

return ZSkipList








-- local ZSet = class "ZSet"

-- function ZSet:ctor()
-- 	self.zsl = {}

-- 	self.dict = {}		--哈希表
-- end

-- function ZSet:zsetAdd(ele, score)
-- 	-- /* Turn options into simple to check vars. */
-- 	local incr = (ele.flags & ZADD_IN_INCR) ~= 0
-- 	local nx   = (ele.flags & ZADD_IN_NX) ~= 0
-- 	local xx   = (ele.flags & ZADD_IN_XX) ~= 0
-- 	local gt   = (ele.flags & ZADD_IN_GT) ~= 0
-- 	local lt   = (ele.flags & ZADD_IN_LT) ~= 0
-- 	local out_flags = 0 -- /* We'll return our response flags. */

-- 	-- /* NaN as input is an error regardless of all the other parameters. */
-- 	if self:isNaN(score) then
-- 		out_flags = ZADD_OUT_NAN
-- 		return false, out_flags
-- 	end

-- 	local de = self:dictFind(ele)
-- 	if de then
-- 		-- /* NX? Return, same element already exists. */
-- 		if nx then
-- 			out_flags = out_flags | ZADD_OUT_NOP
-- 			return true, out_flags
-- 		end

-- 		local curscore = self:dictGetVal(de)

-- 		-- /* Prepare the score for the increment if needed. */
-- 		if incr then
-- 			score = curscore + score
-- 			if self:isNaN(score) then
-- 				out_flags = out_flags | ZADD_OUT_NAN
-- 				return false, out_flags
-- 			end
-- 		end

-- 		-- /* GT/LT? Only update if score is greater/less than current. */
-- 		if (lt and score >= curscore) or (gt and score <= curscore) then
-- 			out_flags = out_flags | ZADD_OUT_NOP
-- 			return true, out_flags
-- 		end

-- 		-- /* Remove and re-insert when score changes. */
-- 		if score ~= curscore then
-- 			zslUpdateScore(ele, score)
-- 			dictSetVal(de, score)
-- 			out_flags = out_flags | ZADD_OUT_UPDATED
-- 		end

-- 		return true, out_flags
-- 	elseif not xx then
-- 		local znode = zslInsert(ele, score)
-- 		dictAdd(ele, znode, score)
-- 		out_flags = out_flags | ZADD_OUT_ADDED
-- 		return true, out_flags
-- 	else
-- 		out_flags = out_flags | ZADD_OUT_NOP
-- 		return true, out_flags
-- 	end
-- end

-- function ZSet:dictFind(ele)
-- 	return self.dict[ele.key]
-- end

-- function ZSet:dictGetVal(dictEntry)
-- 	return dictEntry.score
-- end

-- function ZSet:dictSetVal(dictEntry, val)
-- 	dictEntry.score = val
-- end

-- function ZSet:dictAdd(ele, znode, score)
-- 	local dictEntry = {}
-- 	dictEntry.score = score
-- 	dictEntry.data = ele.data
-- 	dictEntry.zslelePtr = znode
-- 	self.dict[ele.key] = dictEntry
-- end

-- function ZSet:isNaN(value)
-- 	 local num = tonumber(value)
-- 	if num == nil then
-- 		return false
-- 	end

-- 	return num ~= num
-- end

-- return ZSet
