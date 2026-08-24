import Component from "@glimmer/component";
import MashReviewDashboard from "discourse/plugins/mash-review-dashboard/discourse/components/mash-review-dashboard";

export default class MashReviewDashboardConnector extends Component {
  static shouldRender(_args, context, owner) {
    const router = owner.lookup("service:router");
    const currentUser = owner.lookup("service:current-user");

    return Boolean(
      context.siteSettings.mash_review_dashboard_enabled &&
      currentUser?.staff &&
      router.currentURL?.match(/^\/review(?:[/?]|$)/)
    );
  }

  <template><MashReviewDashboard /></template>
}
