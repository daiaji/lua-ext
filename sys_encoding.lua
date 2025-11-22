local ffi = require 'ffi'

if ffi.os == 'Windows' then
	-- specific to Windows.sdk.kernel32 in lua-ffi-bindings
	-- [Fix] Use pcall to avoid crashing if ffi bindings are not found or incompatible
	local ok, kernel32 = pcall(require, 'ffi.Windows.sdk.kernel32')
	
	if ok and kernel32 then
		ffi.cdef[[
			int SetConsoleOutputCP(unsigned int wCodePageID);
			int SetConsoleCP(unsigned int wCodePageID);
		]]

		local CP_UTF8 = 65001
		
		-- Set output code page (solves print garbage)
		pcall(function() ffi.C.SetConsoleOutputCP(CP_UTF8) end)
		
		-- Set input code page (solves io.read garbage)
		pcall(function() ffi.C.SetConsoleCP(CP_UTF8) end)

		-- [新增] 修复全局 arg 表的编码 (ANSI -> UTF-8)
		-- 这里的 arg 是 Lua 启动时由宿主程序填充的全局变量
		if type(_G.arg) == 'table' then
			local ok_shell, shell32 = pcall(require, 'ffi.Windows.sdk.shell32')
			if ok_shell and shell32 and shell32.get_arguments then
				local args_utf8 = shell32.get_arguments()
				if args_utf8 then
					-- 策略：从后往前匹配。
					-- 系统 args_utf8 通常是: [exe, script, arg1, arg2]
					-- Lua arg 表通常是: keys: -1(exe), 0(script), 1(arg1), 2(arg2)
					-- 我们主要关心 arg[1]...arg[N] 这部分参数的内容正确性
					
					local n_lua_arg = #_G.arg
					local n_sys_arg = #args_utf8
					
					-- 只有当系统参数数量足够覆盖 Lua 参数时才替换
					if n_sys_arg >= n_lua_arg then
						for i = 1, n_lua_arg do
							-- 对应关系：系统参数列表的末尾 N 个元素 对应 Lua arg 的 1..N
							local sys_index = n_sys_arg - n_lua_arg + i
							_G.arg[i] = args_utf8[sys_index]
						end
						
						-- 可选：尝试修复 arg[0] (脚本路径)
						-- 如果 Lua arg[0] 存在，尝试用系统参数中对应的位置修复
						if _G.arg[0] and (n_sys_arg - n_lua_arg) > 0 then
							_G.arg[0] = args_utf8[n_sys_arg - n_lua_arg]
						end
					end
				end
			end
		end
	end
end

return true
