/// Which URLs the shell trusts and which links leave the app (pure; tested in
/// test/url_policy_test.dart).
library;

/// The only site allowed to use the native bridge and to stay inside the WebView.
const String trustedHost = 'koe-app.pages.dev';
const String appUrl = 'https://$trustedHost/';

/// Sites the web app sends the whole page to and expects to come back from in the
/// same WebView: Stripe Checkout (and its 3-D Secure pages such as
/// hooks.stripe.com) redirects back to koe-app.pages.dev after the paid sign-up;
/// opening it in the browser would leave the result there.
const String inAppDomain = 'stripe.com';

bool _isInAppHost(String host) => host == inAppDomain || host.endsWith('.$inAppDomain');

/// True only for https pages on [trustedHost].
bool isTrustedUrl(String? url) {
  if (url == null) return false;
  final uri = Uri.tryParse(url);
  return uri != null && uri.scheme == 'https' && uri.host == trustedHost;
}

/// True when a main-frame navigation to [url] should open in the external browser
/// (or the app that handles it, e.g. mail or Play) instead of the WebView.
bool shouldOpenExternally(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  switch (uri.scheme) {
    case 'about':
    case 'data':
    case 'blob':
    case 'javascript':
      return false;
    case 'https':
      return uri.host != trustedHost && !_isInAppHost(uri.host);
    default:
      // http, mailto, tel, intent, market, ...
      return true;
  }
}
