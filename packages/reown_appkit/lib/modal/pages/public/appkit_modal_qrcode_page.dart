import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:reown_appkit/modal/services/toast_service/i_toast_service.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:shimmer/shimmer.dart';

import 'package:reown_appkit/modal/constants/key_constants.dart';
import 'package:reown_appkit/modal/constants/style_constants.dart';
import 'package:reown_appkit/modal/widgets/buttons/simple_icon_button.dart';
import 'package:reown_appkit/modal/widgets/qr_code_view.dart';
import 'package:reown_appkit/modal/widgets/miscellaneous/responsive_container.dart';
import 'package:reown_appkit/modal/widgets/modal_provider.dart';
import 'package:reown_appkit/modal/widgets/navigation/navbar.dart';
import 'package:reown_appkit/modal/services/toast_service/models/toast_message.dart';

class ReownAppKitModalQRCodePage extends StatefulWidget {
  const ReownAppKitModalQRCodePage() : super(key: KeyConstants.qrCodePageKey);

  @override
  State<ReownAppKitModalQRCodePage> createState() =>
      _AppKitModalQRCodePageState();
}

class _AppKitModalQRCodePageState extends State<ReownAppKitModalQRCodePage> {
  IReownAppKitModal? _appKitModal;
  Widget? _qrQodeWidget;
  //

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _appKitModal = ModalProvider.of(context).instance;
      _appKitModal!.addListener(_buildWidget);
      _appKitModal!.appKit!.core.pairing.onPairingExpire.subscribe(
        _onPairingExpire,
      );
      // Guard the connection-URI build. `addPostFrameCallback` does not await
      // this async callback, so anything thrown here escapes as an UNCAUGHT
      // (fatal) error. buildConnectionUri() -> ReownAppKit.connect() ->
      // ReownSign.connect() runs confirmOnlineStateOrThrow(), which throws
      // `ReownCoreError(code: -1, message: No internet connection)` on an
      // offline device, behind a captive portal, or where walletconnect.com is
      // blocked. Opening the QR modal with no connectivity is an ordinary user
      // action and must show an error, not take the app down.
      //
      // Observed downstream as mobile-news MOBILE-NEWS-QM.
      await _safeBuildConnectionUri();
    });
  }

  /// Builds the pairing URI, containing any throw. Never rethrows — the caller
  /// is an un-awaited async callback, so an escaping error is fatal.
  Future<void> _safeBuildConnectionUri() async {
    try {
      await _appKitModal!.buildConnectionUri();
    } catch (_) {
      if (!mounted) return;
      GetIt.I<IToastService>().show(
        ToastMessage(
          type: ToastType.error,
          text: 'Connection failed. Check your network.',
        ),
      );
    }
  }

  void _buildWidget() => setState(() {
    _qrQodeWidget = QRCodeView(
      uri: _appKitModal!.wcUri!,
      logoPath: 'lib/modal/assets/png/logo_wc.png',
    );
  });

  // Same exposure as initState: this is an `async void` event handler, so the
  // future is un-awaited and a throw from buildConnectionUri() (offline /
  // captive portal — MOBILE-NEWS-QM) would be fatal. A pairing can just as
  // easily expire while connectivity is down as at first open. The `mounted`
  // check also stops setState firing on a disposed State.
  void _onPairingExpire(EventArgs? args) async {
    await _safeBuildConnectionUri();
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() async {
    _appKitModal!.appKit!.core.pairing.onPairingExpire.unsubscribe(
      _onPairingExpire,
    );
    _appKitModal!.removeListener(_buildWidget);
    _appKitModal!.expirePreviousInactivePairings();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeData = ReownAppKitModalTheme.getDataOf(context);
    final themeColors = ReownAppKitModalTheme.colorsOf(context);
    final radiuses = ReownAppKitModalTheme.radiusesOf(context);
    final isPortrait = ResponsiveData.isPortrait(context);

    return ModalNavbar(
      title: 'WalletConnect',
      body: SingleChildScrollView(
        scrollDirection: isPortrait ? Axis.vertical : Axis.horizontal,
        child: Flex(
          direction: isPortrait ? Axis.vertical : Axis.horizontal,
          children: [
            Padding(
              padding: EdgeInsets.all(20.0),
              child:
                  _qrQodeWidget ??
                  AspectRatio(
                    aspectRatio: 1.0,
                    child: Shimmer.fromColors(
                      baseColor: themeColors.grayGlass100,
                      highlightColor: themeColors.grayGlass025,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(radiuses.radiusL),
                          color: themeColors.grayGlass010,
                        ),
                      ),
                    ),
                  ),
            ),
            Container(
              constraints: BoxConstraints(
                maxWidth: isPortrait
                    ? ResponsiveData.maxWidthOf(context)
                    : (ResponsiveData.maxHeightOf(context) -
                          kNavbarHeight -
                          32.0),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Scan this QR code with your phone',
                    textAlign: TextAlign.center,
                    style: themeData.textStyles.paragraph500.copyWith(
                      color: themeColors.foreground100,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: kPadding12),
                    child: SimpleIconButton(
                      onTap: () => _copyToClipboard(context),
                      leftIcon: 'lib/modal/assets/icons/copy_14.svg',
                      iconSize: 13.0,
                      title: 'Copy link',
                      fontSize: 14.0,
                      backgroundColor: Colors.transparent,
                      foregroundColor: themeColors.foreground200,
                      overlayColor: WidgetStateProperty.all<Color>(
                        themeColors.background200,
                      ),
                      withBorder: false,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    final service = ModalProvider.of(context).instance;
    await Clipboard.setData(ClipboardData(text: service.wcUri!));
    GetIt.I<IToastService>().show(
      ToastMessage(type: ToastType.success, text: 'Link copied'),
    );
  }
}
