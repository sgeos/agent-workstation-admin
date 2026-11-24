-- Health Alert: runs ~/.local/bin/health-alert --print and shows each alert it
-- prints, so that macOS names the alerts "Health Alert" rather than "sh".
-- Compiled into ~/Applications/Health Alert.app by build.sh in this folder.

on run
	try
		set output to do shell script "/bin/sh \"$HOME/.local/bin/health-alert\" --print || true"
	on error
		-- The checker logs its own errors; there is nothing to show.
		return
	end try
	if output is "" then return
	repeat with alertLine in paragraphs of output
		set savedDelimiters to AppleScript's text item delimiters
		set AppleScript's text item delimiters to "|"
		set fields to text items of (alertLine as text)
		set AppleScript's text item delimiters to savedDelimiters
		if (count of fields) is 3 then
			set alertLevel to item 1 of fields
			set alertTitle to item 2 of fields
			set alertText to item 3 of fields
			if alertLevel is "critical" then
				-- A modal alert blocks this applet until it is dismissed, and launchd
				-- starts no new run while one is still running. On 2026-11-21 a
				-- critical alert at 00:30 went unanswered overnight and stopped all
				-- sampling for eight hours. The alert now gives up after nine
				-- minutes, inside the ten-minute interval, and an unanswered alert is
				-- posted as a notification so that it stays in Notification Center.
				set answer to display alert alertTitle message alertText as critical giving up after 540
				if gave up of answer then
					display notification alertText with title alertTitle sound name "Basso"
				end if
			else
				display notification alertText with title alertTitle sound name "Basso"
			end if
		end if
	end repeat
end run
