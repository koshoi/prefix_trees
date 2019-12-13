local M = {}

box.cfg{
	listen       = '127.0.0.1:3333';
	memtx_memory = 1024 * 1024 * 1024 * 1;
	background   = false;
}

local tree = box.schema.create_space('tree', { if_not_exists = true })

tree:format({
	{ name = 'id',       type = 'number'                      };
	{ name = 'parent',   type = 'number'                      };
	{ name = 'symbol',   type = 'string'                      };
	{ name = 'rule',     type = 'string', is_nullable = true  };
	{ name = 'prefix',   type = 'string'                      };
})

tree:create_index('primary', {
	type          = 'tree';
	parts         = { 'id' };
	if_not_exists = true;
})

tree:create_index('path', {
	type          = 'tree';
	parts         = { 'parent', 'symbol' };
	if_not_exists = true;
})

local MAX_ID = 0

if tree.index.primary:max() then
	MAX_ID = tree.index.primary:max().id
end

local function new_node(node)
	if not node.id then
		MAX_ID = MAX_ID + 1
		node.id = MAX_ID
	end

	if not node.parent then
		node.parent = node.id
	end

	if not node.symbol then
		node.symbol = node.prefix:sub(1, 1)
	end

	return node
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
	tree:insert(tree:frommap(new_node({ prefix = '' })))
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

		local nnode = tree.index.path:get({ cnode.id, pfxrule.p:sub(i, i) })
		if not nnode then
			break
		end

		cnode = nnode
	end

	if old_leftover ~= '' then
		local new_nodes = {}
		new_nodes.split_upper = new_node{
			parent   = cnode.parent;
			prefix   = lp;
		}

		new_nodes.split_lower = new_node{
			id       = cnode.id;
			parent   = new_nodes.split_upper.id;
			prefix   = old_leftover;
			rule     = cnode.rule;
		}

		if new_leftover == '' then
			new_nodes.split_upper.rule = pfxrule.r
		else
			new_nodes.extra = new_node{
				parent   = new_nodes.split_upper.id;
				prefix   = new_leftover;
				rule     = pfxrule.r;
			}
		end

		box.atomic(function()
			tree:delete(cnode.id)
			for _, node in pairs(new_nodes) do
				tree:insert(tree:frommap(node))
			end
		end)
	elseif new_leftover ~= '' then
		tree:insert(tree:frommap(new_node({
			parent   = cnode.id;
			prefix   = new_leftover;
			rule     = pfxrule.r;
		})))
	else
		if cnode.rule ~= nil then
			error(("Prefix=%s appeared twice"):format(pfxrule.p))
		else
			tree:update(cnode.id, {{ '=', 4, pfxrule.r }})
		end
	end
end

function M.walk(entry, prefix)
	local node      = entry
	local left      = prefix
	local collected = {}

	local done = false
	while node do
		local nnode = tree.index.path:get({ node.id, left:sub(1, 1) })

		if not nnode then
			return collected
		end

		local pfx  = nnode.prefix
		local nlen = pfx:len()
		local cut  = left:sub(1, nlen)
		if cut == pfx then
			left = left:sub(nlen + 1, -1)
			node = nnode
			if node.rule ~= nil then
				table.insert(collected, node.rule)
			end
		else
			return collected
		end
	end
end

return M
