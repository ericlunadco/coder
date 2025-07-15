// biome-ignore lint/nursery/noRestrictedImports: createTheme
import { createTheme } from "@mui/material/styles";
import { BODY_FONT_FAMILY, borderRadius } from "../constants";
import { components } from "../mui";
import tw from "../tailwindColors";

const muiTheme = createTheme({
	palette: {
		mode: "dark",
		primary: {
			main: tw.workforce.yellow.main,
			contrastText: tw.black,
			light: tw.workforce.yellow.light,
			dark: tw.workforce.yellow.dark,
		},
		secondary: {
			main: tw.zinc[500],
			contrastText: tw.zinc[200],
			dark: tw.zinc[400],
		},
		background: {
			default: tw.workforce.background.primary,
			paper: tw.workforce.background.secondary,
		},
		text: {
			primary: tw.zinc[50],
			secondary: tw.zinc[400],
			disabled: tw.zinc[500],
		},
		divider: tw.zinc[700],
		warning: {
			light: tw.workforce.yellow.light,
			main: tw.workforce.yellow.main,
			dark: tw.workforce.yellow.dark,
		},
		success: {
			main: tw.workforce.success,
			dark: tw.workforce.yellow.dark,
		},
		info: {
			light: tw.workforce.queued,
			main: tw.workforce.processing,
			dark: tw.workforce.processingBg,
			contrastText: tw.zinc[200],
		},
		error: {
			light: tw.workforce.error,
			main: tw.workforce.error,
			dark: tw.workforce.errorBg,
			contrastText: tw.zinc[200],
		},
		action: {
			hover: tw.zinc[800],
		},
		neutral: {
			main: tw.zinc[50],
		},
		dots: tw.zinc[500],
	},
	typography: {
		fontFamily: BODY_FONT_FAMILY,

		body1: {
			fontSize: "1rem" /* 16px at default scaling */,
			lineHeight: "160%",
		},

		body2: {
			fontSize: "0.875rem" /* 14px at default scaling */,
			lineHeight: "160%",
		},
	},
	shape: {
		borderRadius,
	},
	components,
});

export default muiTheme;
