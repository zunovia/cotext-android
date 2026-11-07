import 'package:cotext/url_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only https pages on koe-app.pages.dev are trusted', () {
    expect(isTrustedUrl('https://koe-app.pages.dev/'), isTrue);
    expect(isTrustedUrl('https://koe-app.pages.dev/koeyaku?x=1#y'), isTrue);
    expect(isTrustedUrl('http://koe-app.pages.dev/'), isFalse);
    expect(isTrustedUrl('https://evil.koe-app.pages.dev/'), isFalse);
    expect(isTrustedUrl('https://koe-app.pages.dev.evil.com/'), isFalse);
    expect(isTrustedUrl('https://abc123.koe-app.pages.dev/'), isFalse); // preview deploys
    expect(isTrustedUrl('https://console.groq.com/keys'), isFalse);
    expect(isTrustedUrl('about:blank'), isFalse);
    expect(isTrustedUrl(''), isFalse);
    expect(isTrustedUrl(null), isFalse);
  });

  test('other sites and apps open outside the WebView', () {
    expect(shouldOpenExternally('https://console.groq.com/keys'), isTrue);
    expect(
        shouldOpenExternally('https://play.google.com/store/apps/details?id=online.surc.cotext'),
        isTrue);
    expect(shouldOpenExternally('https://surc.online/'), isTrue);
    expect(shouldOpenExternally('http://koe-app.pages.dev/'), isTrue);
    expect(shouldOpenExternally('mailto:info@surc.online'), isTrue);
    expect(shouldOpenExternally('market://details?id=online.surc.cotext'), isTrue);
  });

  test('the app itself and inline documents stay inside', () {
    expect(shouldOpenExternally('https://koe-app.pages.dev/settings'), isFalse);
    // The paid plan is gone, so Stripe pages no longer need to stay in the WebView.
    expect(shouldOpenExternally('https://checkout.stripe.com/c/pay/cs_test_123'), isTrue);
    expect(shouldOpenExternally('https://hooks.stripe.com/3d_secure_2/hosted'), isTrue);
    expect(shouldOpenExternally('about:blank'), isFalse);
    expect(shouldOpenExternally('data:text/plain,hello'), isFalse);
    expect(shouldOpenExternally('blob:https://koe-app.pages.dev/1234'), isFalse);
  });
}
