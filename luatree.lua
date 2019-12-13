local json = require 'json'

local M = {}

local node_mt = {
	__tostring = function(self)
		return json.encode({ prefix = self.prefix, rule = self.rule or json.NULL })
	end;

	__serialize = function(self)
		return tostring(self)
	end;
}

local function new_node(node)
	if node.parent then
		if not node.parent.children then
			node.parent.children = {}
		end
		node.parent.children[node.prefix:sub(1, 1)] = node
	end

	return setmetatable(node, node_mt)
end

-- Common Longest Prefix
function clp(str1, str2)
	local longest = 0
	for i = 1, str1:len() do
		if str1:sub(i, i) ~= str2:sub(i, i) then
			break
		else
			longest = i
		end
	end

	return str1:sub(1, longest), str1:sub(longest + 1, -1), str2:sub(longest + 1, -1)
end

function M.create_entry_node()
	local node = new_node({
		prefix = '';
	})
	node.parent = node
	return node
end

function M.add_node(entry, pfxrule)
	local cnode = entry
	local i = 1
	local lp, old_leftover, new_leftover = '', '', ''

	while true do
		lp, old_leftover, new_leftover = clp(cnode.prefix, pfxrule.p:sub(i, -1))
		i = i + lp:len()
		if old_leftover ~= '' then
			break
		end

		local nnode = (cnode.children or {})[pfxrule.p:sub(i, i)]

		if not nnode then
			break
		end

		cnode = nnode
	end

	if old_leftover ~= '' then
		local split_upper = new_node{
			prefix = lp;
			parent = cnode.parent;
		}

		local split_lower = new_node{
			prefix   = old_leftover;
			parent   = split_upper;
			rule     = cnode.rule;
			children = cnode.children;
		}

		if new_leftover == '' then
			split_upper.rule = pfxrule.r
		else
			new_node{
				prefix = new_leftover;
				parent = split_upper;
				rule   = pfxrule.r;
			}
		end

		if cnode.children then
			for _, child in pairs(cnode.children) do
				child.parent = split_lower
			end
		end
	elseif new_leftover ~= '' then
		new_node{
			parent = cnode;
			prefix = new_leftover;
			rule   = pfxrule.r;
		}
	else
		if cnode.rule then
			error(("Prefix=%s appeared twice"):format(pfxrule.p))
		else
			cnode.rule = pfxrule.r
		end
	end
end

function M.walk(entry, prefix)
	local node      = entry
	local left      = prefix
	local collected = {}

	while node do
		local nnode = (node.children or {})[left:sub(1, 1)]

		if not nnode then
			return collected
		end

		local pfx  = nnode.prefix
		local nlen = pfx:len()
		local cut  = left:sub(1, nlen)
		if cut == pfx then
			left = left:sub(nlen + 1, -1)
			node = nnode
			if node.rule then
				table.insert(collected, node.rule)
			end
		else
			return collected
		end
	end
end

return M
