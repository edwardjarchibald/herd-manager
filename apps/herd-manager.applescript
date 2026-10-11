-- Herd Manager: open (or bring to front) the herd manager window.
try
	do shell script "export PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\"; herd manager --window"
on error errMsg
	display alert "Herd Manager" message errMsg
end try
