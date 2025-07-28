export const pageTitle = (...crumbs: string[]): string => {
	return [...crumbs, "Workbench"].join(" - ");
};
