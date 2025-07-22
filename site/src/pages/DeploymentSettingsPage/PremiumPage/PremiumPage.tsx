// import { useDashboard } from "modules/dashboard/useDashboard";
// import type { FC } from "react";
// import { Helmet } from "react-helmet-async";
// import { pageTitle } from "utils/page";
// import { PremiumPageView } from "./PremiumPageView";

// const PremiumPage: FC = () => {
// 	const { entitlements } = useDashboard();

// 	return (
// 		<>
// 			<Helmet>
// 				<title>{pageTitle("Premium Features")}</title>
// 			</Helmet>
// 			<PremiumPageView isEnterprise={entitlements.has_license} />
// 		</>
// 	);
// };

// export default PremiumPage;

// Temporary placeholder component
import type { FC } from "react";

const PremiumPage: FC = () => {
	return (
		<div style={{ padding: "2rem", textAlign: "center" }}>
			<h1>Features</h1>
			<p>All features are available in this deployment.</p>
		</div>
	);
};

export default PremiumPage;
