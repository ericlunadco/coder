import CircularProgress from "@mui/material/CircularProgress";
import FormControl from "@mui/material/FormControl";
import FormControlLabel from "@mui/material/FormControlLabel";
import Radio from "@mui/material/Radio";
import RadioGroup from "@mui/material/RadioGroup";
import {
	type TerminalFontName,
	TerminalFontNames,
	type UpdateUserAppearanceSettingsRequest,
} from "api/typesGenerated";
import { ErrorAlert } from "components/Alert/ErrorAlert";
import { Stack } from "components/Stack/Stack";
import type { FC } from "react";
import {
	DEFAULT_TERMINAL_FONT,
	terminalFontLabels,
	terminalFonts,
} from "theme/constants";
import { Section } from "../Section";

interface AppearanceFormProps {
	isUpdating?: boolean;
	error?: unknown;
	initialValues: UpdateUserAppearanceSettingsRequest;
	onSubmit: (values: UpdateUserAppearanceSettingsRequest) => Promise<unknown>;
}

export const AppearanceForm: FC<AppearanceFormProps> = ({
	isUpdating,
	error,
	onSubmit,
	initialValues,
}) => {
	const currentTerminalFont =
		initialValues.terminal_font || DEFAULT_TERMINAL_FONT;

	const onChangeTerminalFont = async (terminalFont: TerminalFontName) => {
		if (isUpdating) {
			return;
		}
		await onSubmit({
			theme_preference: "dark",
			terminal_font: terminalFont,
		});
	};

	return (
		<form>
			{Boolean(error) && <ErrorAlert error={error} />}

			<Section
				title={
					<Stack direction="row" alignItems="center">
						<span>Terminal Font</span>
						{isUpdating && <CircularProgress size={16} />}
					</Stack>
				}
				layout="fluid"
			>
				<FormControl>
					<RadioGroup
						aria-labelledby="fonts-radio-buttons-group-label"
						defaultValue={currentTerminalFont}
						name="fonts-radio-buttons-group"
						onChange={(_, value) =>
							onChangeTerminalFont(toTerminalFontName(value))
						}
					>
						{TerminalFontNames.filter((name) => name !== "").map((name) => (
							<FormControlLabel
								key={name}
								value={name}
								control={<Radio />}
								label={
									<div css={{ fontFamily: terminalFonts[name] }}>
										{terminalFontLabels[name]}
									</div>
								}
							/>
						))}
					</RadioGroup>
				</FormControl>
			</Section>
		</form>
	);
};

function toTerminalFontName(value: string): TerminalFontName {
	return TerminalFontNames.includes(value as TerminalFontName)
		? (value as TerminalFontName)
		: "";
}
