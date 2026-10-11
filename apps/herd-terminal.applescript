-- Herd Terminal: open the manager (if needed) plus a new herd session window.
try
	do shell script "export PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\"; herd app"
on error errMsg
	display alert "Herd Terminal" message errMsg
end try
