trial () {
	local trial_dir
	trial_dir=$(mk-trial.rb "$@") 
	if [[ -n "$trial_dir" && -d "$trial_dir" ]]
	then
		cd "$trial_dir"
	fi
}
