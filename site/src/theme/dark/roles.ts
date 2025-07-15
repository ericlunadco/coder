import type { Roles } from "../roles";
import colors from "../tailwindColors";

const roles: Roles = {
	danger: {
		background: colors.workforce.retryingBg,
		outline: colors.workforce.retrying,
		text: colors.workforce.retryingText,
		fill: {
			solid: colors.workforce.retrying,
			outline: colors.workforce.retrying,
			text: colors.white,
		},
		disabled: {
			background: colors.workforce.retryingBg,
			outline: colors.orange[800],
			text: colors.orange[300],
			fill: {
				solid: colors.orange[800],
				outline: colors.orange[800],
				text: colors.white,
			},
		},
		hover: {
			background: colors.orange[900],
			outline: colors.workforce.retrying,
			text: colors.white,
			fill: {
				solid: colors.orange[600],
				outline: colors.orange[600],
				text: colors.white,
			},
		},
	},
	error: {
		background: colors.workforce.errorBg,
		outline: colors.workforce.error,
		text: colors.workforce.errorText,
		fill: {
			solid: colors.workforce.error,
			outline: colors.workforce.error,
			text: colors.white,
		},
	},
	warning: {
		background: colors.workforce.yellow.background,
		outline: colors.workforce.yellow.light,
		text: colors.workforce.yellow.text,
		fill: {
			solid: colors.workforce.yellow.main,
			outline: colors.workforce.yellow.main,
			text: colors.black,
		},
	},
	notice: {
		background: colors.workforce.queuedBg,
		outline: colors.workforce.queued,
		text: colors.workforce.queuedText,
		fill: {
			solid: colors.workforce.queued,
			outline: colors.workforce.queued,
			text: colors.white,
		},
	},
	info: {
		background: colors.zinc[950],
		outline: colors.zinc[400],
		text: colors.zinc[50],
		fill: {
			solid: colors.zinc[500],
			outline: colors.zinc[600],
			text: colors.white,
		},
	},
	success: {
		background: colors.workforce.successBg,
		outline: colors.workforce.success,
		text: colors.workforce.successText,
		fill: {
			solid: colors.workforce.success,
			outline: colors.workforce.success,
			text: colors.black,
		},
		disabled: {
			background: colors.workforce.successBg,
			outline: colors.yellow[800],
			text: colors.yellow[300],
			fill: {
				solid: colors.yellow[800],
				outline: colors.yellow[800],
				text: colors.white,
			},
		},
		hover: {
			background: colors.yellow[900],
			outline: colors.workforce.success,
			text: colors.white,
			fill: {
				solid: colors.workforce.yellow.dark,
				outline: colors.workforce.yellow.dark,
				text: colors.black,
			},
		},
	},
	active: {
		background: colors.workforce.processingBg,
		outline: colors.workforce.processing,
		text: colors.workforce.processingText,
		fill: {
			solid: colors.workforce.processing,
			outline: colors.workforce.processing,
			text: colors.white,
		},
		disabled: {
			background: colors.workforce.processingBg,
			outline: colors.green[800],
			text: colors.green[300],
			fill: {
				solid: colors.green[800],
				outline: colors.green[800],
				text: colors.white,
			},
		},
		hover: {
			background: colors.green[900],
			outline: colors.workforce.processing,
			text: colors.white,
			fill: {
				solid: colors.green[600],
				outline: colors.green[600],
				text: colors.white,
			},
		},
	},
	inactive: {
		background: colors.workforce.stoppedBg,
		outline: colors.workforce.stopped,
		text: colors.workforce.stoppedText,
		fill: {
			solid: colors.workforce.stopped,
			outline: colors.workforce.stopped,
			text: colors.white,
		},
	},
	preview: {
		background: colors.violet[950],
		outline: colors.violet[500],
		text: colors.violet[50],
		fill: {
			solid: colors.violet[400],
			outline: colors.violet[400],
			text: colors.white,
		},
	},
};

export default roles;
