import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Every icon in the app, in one place.
///
/// The app previously drew from Material Icons and had drifted across three
/// styles at once — 71 outlined, the rest filled, plus a few stray `_rounded`
/// ones. `fitness_center` appeared five times filled and five times outlined on
/// the same kind of surface. Routing every icon through here means a style can
/// only drift in one file, not fifty.
///
/// Convention: **Regular is the default.** Fill is reserved for a genuinely
/// active or selected state — the current bottom-nav tab, a completed step, a
/// success marker. Pairs that need both are named `x` / `xActive`.
///
/// Names deliberately mirror the Material names they replaced, so the migration
/// stayed a one-to-one rename and the diff is reviewable.
///
/// Adding an icon here grows the bundled icon font, which Shorebird cannot ship
/// in a patch — a new icon means a full store release. Add generously in one go.
abstract final class AppIcons {
  // ── Navigation & chrome ────────────────────────────────────────────────────
  static const home = PhosphorIconsRegular.house;
  static const homeActive = PhosphorIconsFill.house;
  static const chevronRight = PhosphorIconsRegular.caretRight;
  static const chevronLeft = PhosphorIconsRegular.caretLeft;
  static const keyboardArrowDown = PhosphorIconsRegular.caretDown;
  static const keyboardArrowUp = PhosphorIconsRegular.caretUp;
  static const expandMore = PhosphorIconsRegular.caretDown;
  static const arrowDropDown = PhosphorIconsRegular.caretDown;
  static const arrowBack = PhosphorIconsRegular.arrowLeft;
  static const arrowBackIosNew = PhosphorIconsRegular.caretLeft;
  static const close = PhosphorIconsRegular.x;
  static const closeRounded = PhosphorIconsRegular.x;
  static const clear = PhosphorIconsRegular.x;
  static const menu = PhosphorIconsRegular.list;
  static const moreVert = PhosphorIconsRegular.dotsThreeVertical;
  static const moreHoriz = PhosphorIconsRegular.dotsThree;
  static const search = PhosphorIconsRegular.magnifyingGlass;
  static const refresh = PhosphorIconsRegular.arrowsClockwise;
  static const autorenew = PhosphorIconsRegular.arrowsClockwise;
  static const tune = PhosphorIconsRegular.slidersHorizontal;
  static const swapVert = PhosphorIconsRegular.arrowsDownUp;
  static const filterOff = PhosphorIconsRegular.funnelSimple;
  static const layers = PhosphorIconsRegular.stack;
  static const link = PhosphorIconsRegular.link;
  static const allInclusive = PhosphorIconsRegular.infinity;

  // ── Actions ────────────────────────────────────────────────────────────────
  static const add = PhosphorIconsRegular.plus;
  static const addCircle = PhosphorIconsRegular.plusCircle;
  static const removeCircle = PhosphorIconsRegular.minusCircle;
  static const delete = PhosphorIconsRegular.trash;
  static const edit = PhosphorIconsRegular.pencilSimple;
  static const copy = PhosphorIconsRegular.copy;
  static const check = PhosphorIconsRegular.check;
  static const checkCircle = PhosphorIconsRegular.checkCircle;
  static const checkCircleActive = PhosphorIconsFill.checkCircle;
  static const share = PhosphorIconsRegular.shareNetwork;
  static const iosShare = PhosphorIconsRegular.export;
  static const send = PhosphorIconsRegular.paperPlaneTilt;
  static const download = PhosphorIconsRegular.downloadSimple;
  static const uploadFile = PhosphorIconsRegular.uploadSimple;
  static const play = PhosphorIconsRegular.play;
  static const pause = PhosphorIconsRegular.pause;
  static const preview = PhosphorIconsRegular.eye;
  static const visibility = PhosphorIconsRegular.eye;
  static const visibilityOff = PhosphorIconsRegular.eyeSlash;
  static const radioUnchecked = PhosphorIconsRegular.circle;
  static const radioChecked = PhosphorIconsFill.radioButton;

  // ── People & membership ────────────────────────────────────────────────────
  static const person = PhosphorIconsRegular.user;
  static const people = PhosphorIconsRegular.users;
  static const peopleActive = PhosphorIconsFill.users;
  static const groups = PhosphorIconsRegular.usersThree;
  static const groupOff = PhosphorIconsRegular.usersThree;
  static const personAdd = PhosphorIconsRegular.userPlus;
  static const personRemove = PhosphorIconsRegular.userMinus;
  static const personOff = PhosphorIconsRegular.userMinus;
  static const personSearch = PhosphorIconsRegular.userFocus;
  static const manageAccounts = PhosphorIconsRegular.userGear;
  static const howToReg = PhosphorIconsRegular.userCheck;
  static const badge = PhosphorIconsRegular.identificationBadge;
  static const cardMembership = PhosphorIconsRegular.identificationCard;
  static const adminPanel = PhosphorIconsRegular.shieldCheck;

  // ── Money ──────────────────────────────────────────────────────────────────
  static const payments = PhosphorIconsRegular.money;
  static const paymentsActive = PhosphorIconsFill.money;
  static const receipt = PhosphorIconsRegular.receipt;
  static const receiptActive = PhosphorIconsFill.receipt;
  static const creditCard = PhosphorIconsRegular.creditCard;
  static const creditCardActive = PhosphorIconsFill.creditCard;
  static const wallet = PhosphorIconsRegular.wallet;
  static const accountBalance = PhosphorIconsRegular.bank;
  static const sell = PhosphorIconsRegular.tag;

  // ── Gym domain ─────────────────────────────────────────────────────────────
  // Material only had `fitness_center`; Phosphor's barbell reads far better at
  // the small sizes these appear at.
  static const fitness = PhosphorIconsRegular.barbell;
  static const fitnessActive = PhosphorIconsFill.barbell;
  static const restaurant = PhosphorIconsRegular.forkKnife;
  static const qrCode = PhosphorIconsRegular.qrCode;
  static const qrScanner = PhosphorIconsRegular.scan;
  static const fingerprint = PhosphorIconsRegular.fingerprint;

  // ── Time & scheduling ──────────────────────────────────────────────────────
  static const schedule = PhosphorIconsRegular.clock;
  static const accessTime = PhosphorIconsRegular.clock;
  static const history = PhosphorIconsRegular.clockCounterClockwise;
  static const historyToggleOff = PhosphorIconsRegular.clockCountdown;
  static const hourglass = PhosphorIconsRegular.hourglass;
  static const calendarToday = PhosphorIconsRegular.calendarBlank;
  static const calendarMonth = PhosphorIconsRegular.calendar;
  static const dateRange = PhosphorIconsRegular.calendarBlank;
  static const event = PhosphorIconsRegular.calendarBlank;
  static const eventActive = PhosphorIconsFill.calendarBlank;
  static const eventBusy = PhosphorIconsRegular.calendarX;

  // ── Communication ──────────────────────────────────────────────────────────
  static const chat = PhosphorIconsRegular.chatCircle;
  static const chatActive = PhosphorIconsFill.chatCircle;
  static const sms = PhosphorIconsRegular.chatText;
  static const mail = PhosphorIconsRegular.envelopeSimple;
  static const call = PhosphorIconsRegular.phone;
  static const campaign = PhosphorIconsRegular.megaphone;
  static const supportAgent = PhosphorIconsRegular.headset;
  static const notifications = PhosphorIconsRegular.bell;

  // ── Status & feedback ──────────────────────────────────────────────────────
  static const info = PhosphorIconsRegular.info;
  static const error = PhosphorIconsRegular.warningCircle;
  static const cloudOff = PhosphorIconsRegular.cloudSlash;
  static const wifiOff = PhosphorIconsRegular.wifiSlash;
  static const trendingUp = PhosphorIconsRegular.trendUp;
  static const trendingDown = PhosphorIconsRegular.trendDown;
  static const showChart = PhosphorIconsRegular.chartLine;
  static const insights = PhosphorIconsRegular.chartLineUp;
  static const barChart = PhosphorIconsRegular.chartBar;

  // ── Auth & settings ────────────────────────────────────────────────────────
  static const lock = PhosphorIconsRegular.lock;
  static const lockPerson = PhosphorIconsRegular.lockKey;
  static const login = PhosphorIconsRegular.signIn;
  static const logout = PhosphorIconsRegular.signOut;
  static const settings = PhosphorIconsRegular.gear;
  static const business = PhosphorIconsRegular.buildings;

  // ── Media ──────────────────────────────────────────────────────────────────
  static const image = PhosphorIconsRegular.image;
  static const brokenImage = PhosphorIconsRegular.imageBroken;
  static const photoCamera = PhosphorIconsRegular.camera;
  static const addPhoto = PhosphorIconsRegular.imageSquare;
}
