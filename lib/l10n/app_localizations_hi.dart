// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get collectPaymentTitle => 'पेमेंट लें';

  @override
  String get enterAmount => 'रकम डालें';

  @override
  String get enterValidAmount => 'सही रकम डालें';

  @override
  String get alreadyCollectedTitle => 'आज पहले ही ले चुके हैं';

  @override
  String alreadyCollectedBody(String amount, String name, String time) {
    return '$name से आज $time बजे $amount पहले ही ले लिए गए हैं। दूसरा रिन्यूअल लेने से पहले मेंबर को रिफ्रेश करें।';
  }

  @override
  String get renewalDateMissing =>
      'रिन्यूअल की तारीख नहीं मिली। रिफ्रेश करके फिर कोशिश करें।';

  @override
  String get paymentCollected => 'पेमेंट मिल गया';

  @override
  String autoFilled(String hint) {
    return 'अपने-आप भरा: $hint';
  }

  @override
  String get partialPaymentHint =>
      'आंशिक पेमेंट भी ले सकते हैं — पूरे बकाया से कम रकम लेना ठीक है।';

  @override
  String get collectEarlyTitle => 'रिन्यूअल पहले लेना है?';

  @override
  String collectEarlyBody(String date, int days) {
    return 'यह रिन्यूअल $date को ड्यू है ($days दिन बाद)। आगे तभी बढ़ें जब एडवांस पेमेंट मिल चुका हो।';
  }

  @override
  String get collectAdvance => 'एडवांस लें';

  @override
  String get partialPaymentTitle => 'आंशिक पेमेंट';

  @override
  String partialPaymentBody(String entered, String remaining) {
    return 'अभी $entered ले रहे हैं। $remaining बकाया रहेगा।';
  }

  @override
  String get okCollect => 'ठीक है, लें';

  @override
  String get paymentDateFuture => 'पेमेंट की तारीख आगे की नहीं हो सकती';

  @override
  String get validTillAfterPayment =>
      'वैलिड तारीख, पेमेंट की तारीख के बाद की होनी चाहिए';

  @override
  String get validTillLapsed =>
      'यह तारीख निकल चुकी है, इसलिए मेंबर एक्सपायर ही रहेगा। वैलिड तारीख आगे की रखें।';

  @override
  String validTillPartial(String date) {
    return 'मेंबरशिप $date तक वैलिड रहेगी। बाकी रकम ड्यू रहेगी।';
  }

  @override
  String validTillFull(String date) {
    return 'मेंबरशिप $date तक वैलिड रहेगी।';
  }

  @override
  String get retry => 'फिर कोशिश करें';

  @override
  String get seeAll => 'सब देखें';

  @override
  String get add => 'जोड़ें';

  @override
  String get addMember => 'मेंबर जोड़ें';

  @override
  String get collectPayment => 'पेमेंट लें';

  @override
  String get collect => 'पेमेंट लें';

  @override
  String get signOutTitle => 'साइन आउट करें?';

  @override
  String get signOutBody => 'आप कभी भी फिर से साइन इन कर सकते हैं।';

  @override
  String get signOutConfirm => 'साइन आउट करें';

  @override
  String get tourMembers => 'यहाँ अपने सभी जिम मेंबर्स देखें और संभालें।';

  @override
  String get tourCheckIn =>
      'QR स्कैन से मेंबर का चेक-इन करने के लिए यहाँ टैप करें।';

  @override
  String get tourMore =>
      'लीड्स, क्लास, स्टाफ, रिपोर्ट और सेटिंग्स यहाँ मिलेंगे।';

  @override
  String get homeMoneyHint => 'बकाया, पेमेंट, इनवॉइस';

  @override
  String get homeCheckInHint => 'स्कैन या हाज़िरी';

  @override
  String get trialEndsToday => 'ट्रायल आज खत्म हो रहा है';

  @override
  String trialEndsIn(int days) {
    return 'ट्रायल $days दिन में खत्म होगा';
  }

  @override
  String get trialActive => 'ट्रायल चालू है';

  @override
  String planRenewsIn(String plan, int days) {
    return '$plan प्लान · $days दिन में रिन्यू';
  }

  @override
  String get dashboardLoadFailed => 'डैशबोर्ड लोड नहीं हुआ';

  @override
  String get dashboardSubtitle => 'कलेक्शन, बकाया, खर्चे और मुनाफ़ा';

  @override
  String get gettingStarted => 'शुरुआत करें';

  @override
  String get checklistAddMembers =>
      '3 मेंबर जोड़ें — डैशबोर्ड में सब दिखने लगेगा';

  @override
  String get checklistSetFee => 'अपनी महीने की फीस तय करें';

  @override
  String get checklistTryCheckIn => 'एक चेक-इन करके देखें';

  @override
  String get checklistWhatsApp => 'WhatsApp रिमाइंडर चालू करें';

  @override
  String get quickAddMember => 'मेंबर\nजोड़ें';

  @override
  String get quickCollectPayment => 'पेमेंट\nलें';

  @override
  String get quickAddLead => 'लीड\nजोड़ें';

  @override
  String get noPhoneSaved => 'इस मेंबर का फ़ोन नंबर सेव नहीं है';

  @override
  String get whatsappOpenFailed => 'WhatsApp नहीं खुला';

  @override
  String get birthdaysToday => 'आज जन्मदिन';

  @override
  String get wish => 'बधाई दें';

  @override
  String get recentPayments => 'हाल के पेमेंट';

  @override
  String get noPaymentsYet => 'अभी कोई पेमेंट नहीं';

  @override
  String get toCollect => 'लेना बाकी';

  @override
  String get needsAttention => 'ध्यान दें';

  @override
  String overduePayments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count पेमेंट ओवरड्यू',
    );
    return '$_temp0';
  }

  @override
  String amountPending(String amount) {
    return '$amount बाकी';
  }

  @override
  String membershipsDueIn7Days(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count मेंबरशिप 7 दिन में ड्यू',
    );
    return '$_temp0';
  }

  @override
  String get renewBeforeLapse => 'एक्सपायर होने से पहले रिन्यू करें';

  @override
  String leadsNeedFollowUp(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count लीड्स का फ़ॉलो-अप बाकी',
    );
    return '$_temp0';
  }

  @override
  String get followUpPassed => 'फ़ॉलो-अप की तारीख निकल गई';

  @override
  String checkInsWaitingSync(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count चेक-इन सिंक होने बाकी',
    );
    return '$_temp0';
  }

  @override
  String get savedOfflineSync => 'ऑफ़लाइन सेव · इंटरनेट आने पर सिंक होगा';

  @override
  String get paymentDueToday => 'आज ड्यू पेमेंट';

  @override
  String get noPaymentsDueToday => 'आज कोई पेमेंट ड्यू नहीं';

  @override
  String get collectedByMode => 'पेमेंट मोड के हिसाब से कलेक्शन';

  @override
  String get expensesByCategory => 'कैटेगरी के हिसाब से खर्चे';

  @override
  String get thisMonth => 'इस महीने';

  @override
  String get noPaymentsThisMonth => 'इस महीने अभी कोई पेमेंट नहीं';

  @override
  String get noExpensesThisMonth => 'इस महीने कोई खर्चा नहीं लिखा';

  @override
  String get others => 'बाकी';

  @override
  String todayCollected(String amount, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count पेमेंट',
    );
    return 'आज $amount · $_temp0';
  }

  @override
  String get dueIn7Days => '7 दिन में ड्यू';

  @override
  String get lastMonth => 'पिछला महीना';

  @override
  String get collectedHint => 'मिला';

  @override
  String get addExpense => 'खर्चा जोड़ें';

  @override
  String get fullReport => 'पूरी रिपोर्ट';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get save => 'सेव करें';

  @override
  String get required => 'ज़रूरी है';

  @override
  String get noPlansOnMembers => 'अभी किसी मेंबर पर कोई प्लान नहीं।';

  @override
  String get membersLoadFailed =>
      'मेंबर्स लोड नहीं हुए। फिर से देखने के लिए नीचे खींचें।';

  @override
  String get importMembers => 'मेंबर्स इम्पोर्ट करें';

  @override
  String get inviteMembersHint => 'मेंबर्स को ऐप इस्तेमाल करने के लिए बुलाएं';

  @override
  String get openProfile => 'प्रोफ़ाइल खोलें';

  @override
  String get call => 'कॉल करें';

  @override
  String get noMembersHere => 'यहाँ कोई मेंबर नहीं';

  @override
  String get noMembersHereBody =>
      'इस खोज या फ़िल्टर में अभी कोई नहीं मिला। फ़िल्टर हटाएं, या जोड़ें बटन से अपना पहला मेंबर जोड़ें।';

  @override
  String get noPlansYet => 'अभी कोई मेंबरशिप प्लान नहीं';

  @override
  String get noPlansYetBody =>
      'हर मेंबर का प्लान होना चाहिए — उसी से उनके इनवॉइस बनते हैं।';

  @override
  String get createPlan => 'प्लान बनाएं';

  @override
  String get welcomeSent => 'वेलकम मैसेज भेज दिया';

  @override
  String couldNotSendReason(String reason) {
    return 'नहीं भेज पाए — $reason';
  }

  @override
  String get tryAgainLower => 'फिर कोशिश करें';

  @override
  String get welcomeSendFailed => 'वेलकम मैसेज नहीं भेज पाए';

  @override
  String memberAdded(String name) {
    return '$name जुड़ गए';
  }

  @override
  String collectRemaining(String amount) {
    return 'बाकी $amount लें';
  }

  @override
  String get sending => 'भेज रहे हैं…';

  @override
  String get sendWelcomeEnglish => 'वेलकम मैसेज भेजें (अंग्रेज़ी)';

  @override
  String get sendWelcomeHindi => 'वेलकम मैसेज भेजें (हिन्दी)';

  @override
  String get welcomeNeedsOwnerPhone =>
      'वेलकम मैसेज के लिए जिम मालिक का फ़ोन नंबर चाहिए, जो अभी नहीं जुड़ा है। मालिक इसे सेटिंग्स → प्रोफ़ाइल बदलें में जोड़ सकते हैं।';

  @override
  String get shareManually => 'या खुद शेयर करें';

  @override
  String get chooseFromGallery => 'गैलरी से चुनें';

  @override
  String get takePhoto => 'फ़ोटो खींचें';

  @override
  String get createPlanFirst =>
      'पहले मेंबरशिप प्लान बनाएं — इनवॉइस बनाने के लिए मेंबर का प्लान ज़रूरी है';

  @override
  String get planNotAssigned =>
      'मेंबर सेव हो गया, पर प्लान नहीं लगा। मेंबर खोलकर प्लान चुनें।';

  @override
  String get batchNotSet => 'मेंबर जुड़ गया, पर बैच सेट नहीं हुआ।';

  @override
  String paymentNotRecorded(String amount) {
    return 'मेंबर जुड़ गया, पर $amount का पेमेंट दर्ज नहीं हुआ। मेंबर खोलकर पेमेंट लें पर टैप करें।';
  }

  @override
  String memberIdInUse(String id) {
    return 'मेंबर आईडी \"$id\" पहले से इस्तेमाल में है। कोई दूसरी आईडी डालें।';
  }

  @override
  String get addMemberFailed => 'मेंबर नहीं जुड़ा। फिर कोशिश करें।';

  @override
  String get choosePlan => 'प्लान चुनें';

  @override
  String get autoAssignHint => 'खाली छोड़ें, आईडी अपने-आप मिल जाएगी';

  @override
  String get pickPlanFirst => 'पहले मेंबरशिप प्लान चुनें।';

  @override
  String get discountRepeats => 'छूट हर अपने-आप बनने वाले इनवॉइस पर लगेगी।';

  @override
  String get moreThanPayable => 'देय रकम से ज़्यादा';

  @override
  String get fullAmount => 'पूरी रकम';

  @override
  String get addMoreDetails => 'और जानकारी जोड़ें';

  @override
  String get fromThePlan => 'प्लान के हिसाब से';

  @override
  String get memberNotFound => 'मेंबर नहीं मिला';

  @override
  String get memberNotFoundBody =>
      'हो सकता है यह मेंबर आपके जिम से हटा दिया गया हो।';

  @override
  String get deleteMemberTitle => 'मेंबर हटाएं?';

  @override
  String deleteMemberBody(String name) {
    return '$name को हमेशा के लिए हटाएं? उनका सारा डेटा (मेंबरशिप, इनवॉइस, चेक-इन) हट जाएगा। यह वापस नहीं होगा।';
  }

  @override
  String get delete => 'हटाएं';

  @override
  String get deleteMemberFailed => 'मेंबर नहीं हटा';

  @override
  String get deleteMember => 'मेंबर हटाएं';

  @override
  String get renew => 'रिन्यू करें';

  @override
  String get renewPlanTitle => 'प्लान रिन्यू करें?';

  @override
  String renewPlanBody(String amount, String name) {
    return 'इससे $name से $amount लिया हुआ माना जाएगा और उनका प्लान एक साइकिल आगे बढ़ जाएगा। आगे बढ़ने से पहले पक्का करें कि पेमेंट मिल गया है।';
  }

  @override
  String get planRenewed => 'प्लान रिन्यू हो गया';

  @override
  String get addPlan => 'प्लान जोड़ें';

  @override
  String get noActivePlan => 'कोई चालू प्लान नहीं';

  @override
  String get fingerprintHelper => 'फ़िंगरप्रिंट मशीन पर दर्ज कर्मचारी नंबर';

  @override
  String couldNotSaveError(String error) {
    return 'सेव नहीं हुआ: $error';
  }

  @override
  String get notEnrolledInBatch => 'किसी बैच में नहीं है।';

  @override
  String get noCheckInsYet => 'अभी कोई चेक-इन नहीं';

  @override
  String get memberIdCopied => 'मेंबर आईडी कॉपी हो गई';

  @override
  String get sendWhatsApp => 'WhatsApp भेजें';

  @override
  String get typeMessage => 'मैसेज लिखें…';

  @override
  String get sendOnWhatsApp => 'WhatsApp पर भेजें';

  @override
  String get membershipOnHold => 'मेंबरशिप होल्ड पर डाल दी';

  @override
  String get holdRemoved => 'होल्ड हटा दिया';

  @override
  String get statusUpdateFailed => 'स्टेटस अपडेट नहीं हुआ';

  @override
  String get sessionExpired => 'सेशन खत्म हो गया। फिर से साइन इन करें।';

  @override
  String portalInviteSent(String email) {
    return '$email पर पोर्टल इनवाइट भेज दिया';
  }

  @override
  String get inviteSendFailed => 'इनवाइट नहीं भेज पाए';

  @override
  String get cancelMembershipTitle => 'मेंबरशिप रद्द करें?';

  @override
  String cancelMembershipBody(String name) {
    return '$name का अभी का प्लान रद्द हो जाएगा। यह वापस नहीं होगा।';
  }

  @override
  String get keepPlan => 'प्लान रहने दें';

  @override
  String get cancelIt => 'रद्द करें';

  @override
  String get membershipCancelled => 'मेंबरशिप रद्द हो गई';

  @override
  String get cancelMembershipFailed => 'मेंबरशिप रद्द नहीं हुई';

  @override
  String get noFullPlans =>
      'कोई महीने या साल का प्लान नहीं। पहले बिलिंग में प्लान बनाएं।';

  @override
  String get noActivePlans =>
      'कोई चालू प्लान नहीं। पहले बिलिंग में प्लान बनाएं।';

  @override
  String get convertToFullPlanTitle => 'पूरे प्लान में बदलें';

  @override
  String get changePlan => 'प्लान बदलें';

  @override
  String get convert => 'बदलें';

  @override
  String get switchPlan => 'प्लान बदलें';

  @override
  String get recurringDiscountBody =>
      'इस मेंबर के हर अपने-आप बनने वाले इनवॉइस से यह तय रकम कटेगी।';

  @override
  String get confirm => 'पक्का करें';

  @override
  String get noDiscount => 'छूट नहीं';

  @override
  String get convertedToFullPlan => 'पूरे प्लान में बदल दिया';

  @override
  String get planAssigned => 'प्लान लग गया';

  @override
  String get assignPlanFailed => 'प्लान नहीं लगा';

  @override
  String get editDiscountBody =>
      'हर अपने-आप बनने वाले इनवॉइस से यह तय रकम कटेगी। हटाने के लिए 0 रखें।';

  @override
  String get discountUpdated => 'छूट अपडेट हो गई';

  @override
  String get discountUpdateFailed => 'छूट अपडेट नहीं हुई';

  @override
  String get removeHold => 'होल्ड हटाएं';

  @override
  String get holdMembership => 'मेंबरशिप होल्ड करें';

  @override
  String get convertToFullPlan => 'पूरे प्लान में बदलें';

  @override
  String get assignPlan => 'प्लान लगाएं';

  @override
  String editRecurringDiscount(String amount) {
    return 'हर बार की छूट बदलें ($amount कम)';
  }

  @override
  String get addRecurringDiscount => 'हर बार की छूट जोड़ें';

  @override
  String get sendPortalInvite => 'पोर्टल इनवाइट भेजें';

  @override
  String get cancelPlan => 'प्लान रद्द करें';

  @override
  String get startNewPlanFrom => 'नया प्लान कब से शुरू करें?';

  @override
  String currentPlanActiveTill(String date) {
    return 'इनका अभी का प्लान $date तक चालू है।';
  }

  @override
  String todayWithDate(String date) {
    return 'आज ($date)';
  }

  @override
  String get newPlanStartsNow =>
      'नया प्लान अभी से शुरू होगा। पुराने प्लान के बचे दिन हट जाएंगे।';

  @override
  String get newPlanStartsAfter =>
      'नया प्लान पुराना खत्म होने के बाद शुरू होगा। कुछ नहीं हटेगा, कोई गैप नहीं।';

  @override
  String get discountApplied => 'छूट लगी';

  @override
  String get enterValidEmail => 'सही ईमेल पता डालें';

  @override
  String get enterValidMobile => 'सही 10 अंकों का मोबाइल नंबर डालें';

  @override
  String get saveFailed => 'सेव नहीं हुआ। फिर कोशिश करें।';

  @override
  String get editMember => 'मेंबर बदलें';

  @override
  String get saveChanges => 'बदलाव सेव करें';

  @override
  String get moreDetails => 'और जानकारी';

  @override
  String get noActivityYet => 'अभी कोई गतिविधि नहीं';

  @override
  String get noActivityYetBody => 'इस मेंबर में किए गए बदलाव यहाँ दिखेंगे।';

  @override
  String get noMemberPaymentsBody => 'इस मेंबर से लिए गए पेमेंट यहाँ दिखेंगे।';

  @override
  String get selectCollectionDates => 'कलेक्शन की तारीखें चुनें';

  @override
  String get searchByMemberName => 'मेंबर के नाम से खोजें';

  @override
  String get paymentsLoadFailed => 'पेमेंट लोड नहीं हुए';

  @override
  String get checkConnectionRetry =>
      'इंटरनेट देखें, फिर नीचे खींचकर दोबारा देखें।';

  @override
  String get noMatches => 'कुछ नहीं मिला';

  @override
  String noDuesForQuery(String query) {
    return 'इस व्यू में \"$query\" के लिए कोई बकाया नहीं।';
  }

  @override
  String nothingOverdueInDays(int days) {
    return 'पिछले $days दिनों में कुछ ओवरड्यू नहीं';
  }

  @override
  String get viewAllDues => 'सारे बकाया देखें';

  @override
  String olderDuesPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count पुराने बकाया अभी तक न लिए गए, न हटाए गए।',
    );
    return '$_temp0';
  }

  @override
  String get everyonePaid => 'सबने पेमेंट कर दिया';

  @override
  String get everyonePaidBody =>
      'आज कोई बकाया नहीं। इस हफ़्ते ड्यू होने वाले रिन्यूअल यहाँ दिखेंगे।';

  @override
  String get seeUpcomingRenewals => 'आने वाले रिन्यूअल देखें';

  @override
  String get loadingEllipsis => 'लोड हो रहा है…';

  @override
  String get newInvoice => 'नया इनवॉइस';

  @override
  String nothingForQuery(String query) {
    return 'इस टैब में \"$query\" के लिए कुछ नहीं।';
  }

  @override
  String get noPaymentsInDates => 'इन तारीखों में कोई पेमेंट नहीं';

  @override
  String get tryWiderRange => 'तारीखों की रेंज बढ़ाकर देखें।';

  @override
  String get nothingHereYet => 'यहाँ अभी कुछ नहीं';

  @override
  String get paymentsAppearHere =>
      'पहला पेमेंट दर्ज करते ही पेमेंट यहाँ दिखेंगे।';

  @override
  String get invoicesAppearHere => 'आपके बनाए इनवॉइस यहाँ दिखेंगे।';

  @override
  String get deleteInvoiceTitle => 'इनवॉइस हटाएं?';

  @override
  String get deleteInvoiceBody =>
      'यह इनवॉइस और इसके पेमेंट रिकॉर्ड हमेशा के लिए हट जाएंगे। यह वापस नहीं होगा।';

  @override
  String get change => 'बदलें';

  @override
  String get collectEarly => 'पहले लें';

  @override
  String get earlyShort => 'पहले';

  @override
  String alreadyCollectedRecordAgain(
    String amount,
    String time,
    String newAmount,
  ) {
    return 'इस मेंबर से आज $time बजे $amount पहले ही ले लिए गए हैं।\n\n$newAmount फिर से दर्ज करें?';
  }

  @override
  String get recordAnyway => 'फिर भी दर्ज करें';

  @override
  String get paymentRecorded => 'पेमेंट दर्ज हो गया';

  @override
  String get recordPayment => 'पेमेंट दर्ज करें';

  @override
  String get selectMemberFirst => 'पहले मेंबर चुनें';

  @override
  String get createInvoice => 'इनवॉइस बनाएं';

  @override
  String get selectMember => 'मेंबर चुनें';

  @override
  String autoFilledFromPlan(String hint) {
    return 'चालू प्लान से अपने-आप भरा: $hint';
  }

  @override
  String get selectDate => 'तारीख चुनें';

  @override
  String get createSendInvoice => 'इनवॉइस बनाएं और भेजें';

  @override
  String get noPhoneAddInProfile =>
      'इस मेंबर का फ़ोन नंबर सेव नहीं है। पहले उनकी प्रोफ़ाइल में जोड़ें।';

  @override
  String get invoicePdfFailed => 'इनवॉइस PDF नहीं बन पाई';

  @override
  String get noConnection => 'इंटरनेट नहीं है';

  @override
  String get checkInNeedsInternet =>
      'पहली बार चेक-इन के लिए इंटरनेट चाहिए। ऑफ़लाइन मोड चालू करने के लिए एक बार कनेक्ट करें।';

  @override
  String get sessionExpiredShort => 'सेशन खत्म हो गया';

  @override
  String get signInForOffline => 'ऑफ़लाइन चेक-इन के लिए फिर से साइन इन करें।';

  @override
  String get savedOffline => 'ऑफ़लाइन सेव';

  @override
  String get willSyncWhenConnected => 'इंटरनेट आते ही अपने-आप सिंक होगा।';

  @override
  String checkedOutSuccess(String name) {
    return '$name — चेक-आउट हो गया।';
  }

  @override
  String checkoutFailed(String error) {
    return 'चेक-आउट नहीं हुआ: $error';
  }

  @override
  String get invalidQr => 'गलत QR कोड';

  @override
  String get notMemberQr => 'यह GymCRM मेंबर का QR कोड नहीं है।';

  @override
  String get scanNext => 'अगला स्कैन करें';

  @override
  String get searchNameOrId => 'नाम खोजें या मेंबर आईडी डालें';

  @override
  String get noMembersMatchName => 'इस नाम का कोई मेंबर नहीं';

  @override
  String get todaysCheckIns => 'आज के चेक-इन';

  @override
  String get noCheckInsToday => 'आज अभी कोई चेक-इन नहीं';

  @override
  String get staffScansMember => 'स्टाफ मेंबर को स्कैन करे';

  @override
  String get membersScanGym => 'मेंबर जिम को स्कैन करें';

  @override
  String gymQrLoadFailed(String error) {
    return 'जिम QR लोड नहीं हुआ: $error';
  }

  @override
  String get noCheckInCode => 'इस जिम का अभी कोई चेक-इन कोड नहीं।';

  @override
  String get membersScanThis => 'मेंबर इसे स्कैन करके खुद चेक-इन करें';

  @override
  String get checkInLinkCopied => 'चेक-इन लिंक कॉपी हो गया';

  @override
  String get tapToCopyLink => 'चेक-इन लिंक कॉपी करने के लिए टैप करें';

  @override
  String get fullScreenFrontDesk =>
      'फ़्रंट डेस्क पर दिखाने के लिए फ़ुल स्क्रीन';

  @override
  String get savedToGallery => 'गैलरी में सेव हो गया';

  @override
  String get qrSaveFailed => 'QR कोड सेव नहीं हुआ। फिर कोशिश करें।';

  @override
  String get qrShareFailed => 'QR कोड शेयर नहीं हुआ। फिर कोशिश करें।';

  @override
  String get membersScanThisPrint =>
      'मेंबर इसे स्कैन करके खुद चेक-इन करें।\nइसे प्रिंट करके फ़्रंट डेस्क पर लगाएं।';

  @override
  String get saving => 'सेव हो रहा है…';

  @override
  String get saveToGallery => 'गैलरी में सेव करें';

  @override
  String get preparing => 'तैयार हो रहा है…';

  @override
  String checkInsSavedOffline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count चेक-इन ऑफ़लाइन सेव — अभी सिंक करने के लिए टैप करें',
    );
    return '$_temp0';
  }

  @override
  String get checkOut => 'चेक-आउट करें';

  @override
  String get searchMemberName => 'मेंबर का नाम खोजें...';

  @override
  String get noCheckInsFound => 'कोई चेक-इन नहीं मिला';

  @override
  String get featMoney => 'पैसे';

  @override
  String get featCheckIn => 'चेक-इन';

  @override
  String get featMembers => 'मेंबर्स';

  @override
  String get featPlans => 'प्लान';

  @override
  String get featExpenses => 'खर्चे';

  @override
  String get featBiometric => 'बायोमेट्रिक मशीन';

  @override
  String get featAttendance => 'हाज़िरी कैलेंडर';

  @override
  String get featStaff => 'स्टाफ और रोल';

  @override
  String get featLeads => 'लीड्स (पूछताछ)';

  @override
  String get featReminders => 'रिमाइंडर';

  @override
  String get featSignupCode => 'मेंबर साइनअप कोड';

  @override
  String get featBatches => 'बैच';

  @override
  String get featWorkout => 'वर्कआउट प्लान';

  @override
  String get featDiet => 'डाइट प्लान';

  @override
  String get featReports => 'रिपोर्ट';

  @override
  String get featExport => 'डेटा एक्सपोर्ट';

  @override
  String get featActivity => 'एक्टिविटी लॉग';

  @override
  String get featBranches => 'जिम ब्रांच';

  @override
  String get featSettings => 'सेटिंग्स';

  @override
  String get groupRunGym => 'जिम चलाएं';

  @override
  String get groupGrow => 'बढ़ाएं';

  @override
  String get groupPrograms => 'मेंबर प्रोग्राम';

  @override
  String get groupInsights => 'हिसाब-किताब';

  @override
  String get groupSetup => 'सेटअप';

  @override
  String get settingsAccount => 'अकाउंट';

  @override
  String get settingsGym => 'जिम';

  @override
  String get settingsApp => 'ऐप';

  @override
  String get subscription => 'सब्सक्रिप्शन';

  @override
  String get editProfile => 'प्रोफ़ाइल बदलें';

  @override
  String get changePassword => 'पासवर्ड बदलें';

  @override
  String get tryNewDesign => 'नया डिज़ाइन आज़माएं';

  @override
  String get switchBackClassic => 'पुराना डिज़ाइन वापस लाएं';

  @override
  String get gymDetails => 'जिम की जानकारी';

  @override
  String get staffRow => 'स्टाफ';

  @override
  String get invoiceSettings => 'इनवॉइस सेटिंग्स';

  @override
  String get registrationLink => 'रजिस्ट्रेशन लिंक';

  @override
  String get rateUsAppStore => 'App Store पर रेटिंग दें';

  @override
  String get rateUsPlayStore => 'Play Store पर रेटिंग दें';

  @override
  String get whatsNew => 'नया क्या है';

  @override
  String get helpSupport => 'मदद और सपोर्ट';

  @override
  String get privacyChoices => 'प्राइवेसी और डेटा';

  @override
  String get exportGymData => 'जिम डेटा एक्सपोर्ट';

  @override
  String get privacyPolicy => 'प्राइवेसी पॉलिसी';

  @override
  String get termsOfService => 'सेवा की शर्तें';

  @override
  String get aboutGymCRM => 'GymCRM के बारे में';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHindi => 'हिन्दी';
}
