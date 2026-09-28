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

  @override
  String get expenses => 'खर्चे';

  @override
  String get deleteExpenseTitle => 'खर्च हटाएं?';

  @override
  String deleteExpenseBody(Object amount, Object category) {
    return '$category की $amount राशि वाली एंट्री हटाएं? इसे वापस नहीं लिया जा सकता।';
  }

  @override
  String get category => 'श्रेणी';

  @override
  String get amount => 'राशि';

  @override
  String get date => 'तारीख';

  @override
  String get noteOptional => 'नोट (वैकल्पिक)';

  @override
  String get saveExpense => 'खर्च सहेजें';

  @override
  String get noExpensesLogged => 'कोई खर्च दर्ज नहीं है';

  @override
  String get noExpensesLoggedBody =>
      'किराया, वेतन और जिम के अन्य खर्चे यहां दर्ज करें';

  @override
  String errorWithMessage(Object error) {
    return 'गलती: $error';
  }

  @override
  String get staffPermissions => 'स्टाफ अनुमतियां';

  @override
  String get ownersKeepAccess => 'मालिक के पास हमेशा पूरा एक्सेस रहेगा';

  @override
  String get permissionSetupHint =>
      'पहले रोल की डिफ़ॉल्ट अनुमतियां तय करें, फिर जरूरत पर किसी स्टाफ के लिए बदलें।';

  @override
  String get roleDefaults => 'रोल की डिफ़ॉल्ट';

  @override
  String get staffOverride => 'स्टाफ के लिए बदलाव';

  @override
  String get configureRole => 'रोल चुनें';

  @override
  String get manager => 'मैनेजर';

  @override
  String get trainer => 'ट्रेनर';

  @override
  String get staff => 'स्टाफ';

  @override
  String get noStaffToConfigure => 'सेट करने के लिए कोई स्टाफ नहीं है';

  @override
  String get inviteStaffFirst =>
      'पहले किसी मैनेजर, ट्रेनर या स्टाफ को आमंत्रित करें।';

  @override
  String get configureStaffMember => 'स्टाफ सदस्य चुनें';

  @override
  String get useRoleDefault => 'रोल की डिफ़ॉल्ट लगाएं';

  @override
  String get view => 'देखें';

  @override
  String get edit => 'बदलें';

  @override
  String get freeze => 'रोकें';

  @override
  String get export => 'एक्सपोर्ट';

  @override
  String get ownerPermissionsLocked =>
      'मालिक की अनुमतियां कम नहीं की जा सकतीं।';

  @override
  String get permissionDeniedStaffAccess =>
      'आपके पास स्टाफ एक्सेस बदलने की अनुमति नहीं है।';

  @override
  String get permissionsSaveFailed =>
      'अनुमतियां सहेजी नहीं जा सकीं। दोबारा कोशिश करें।';

  @override
  String get gymBranches => 'जिम ब्रांच';

  @override
  String branchesLoadFailed(Object error) {
    return 'ब्रांच लोड नहीं हुईं: $error';
  }

  @override
  String get gym => 'जिम';

  @override
  String get addBranch => 'ब्रांच जोड़ें';

  @override
  String get addGymBranch => 'जिम ब्रांच जोड़ें';

  @override
  String get branchName => 'ब्रांच का नाम';

  @override
  String get cityOptional => 'शहर (वैकल्पिक)';

  @override
  String get branchNameRequired => 'ब्रांच का नाम जरूरी है।';

  @override
  String get createBranch => 'ब्रांच बनाएं';

  @override
  String get memberSignupCode => 'मेंबर साइनअप कोड';

  @override
  String get signupCodeHelp =>
      'मेंबर अपना पोर्टल अकाउंट बनाने के लिए अपने फ़ोन नंबर के साथ यह कोड डालें।';

  @override
  String get noCodeAvailable => 'अभी कोई कोड उपलब्ध नहीं है।';

  @override
  String get gymCodeCopied => 'जिम कोड कॉपी हुआ';

  @override
  String get tapToCopy => 'कॉपी करने के लिए टैप करें';

  @override
  String get shareWithMembers => 'मेंबरों के साथ शेयर करें';

  @override
  String get attendanceCalendar => 'अटेंडेंस कैलेंडर';

  @override
  String get deleteAttendanceTitle => 'अटेंडेंस हटाएं?';

  @override
  String permissionToActionDenied(Object action) {
    return 'आपके पास $action की अनुमति नहीं है।';
  }

  @override
  String get noAttendanceRecorded => 'कोई अटेंडेंस दर्ज नहीं है';

  @override
  String get addAttendance => 'अटेंडेंस जोड़ें';

  @override
  String get editCorrection => 'सुधार बदलें';

  @override
  String get searchMember => 'मेंबर खोजें';

  @override
  String get member => 'मेंबर';

  @override
  String checkInAt(Object time) {
    return 'अंदर $time';
  }

  @override
  String get manualChangeReason => 'हाथ से बदलाव का कारण';

  @override
  String get manualChangeHint => 'उदाहरण: बायोमेट्रिक डिवाइस ऑफ़लाइन थी';

  @override
  String get saveAttendance => 'अटेंडेंस सहेजें';

  @override
  String get reason => 'कारण';

  @override
  String presentCount(Object count) {
    return '$count उपस्थित';
  }

  @override
  String get attendanceEmptyHint =>
      'हाथ से सुधार दर्ज करने के लिए अटेंडेंस जोड़ें चुनें।';

  @override
  String get correctAttendance => 'अटेंडेंस सुधारें';

  @override
  String get selectMemberError => 'एक मेंबर चुनें।';

  @override
  String get clearReasonError => 'साफ़ कारण लिखें (कम से कम 5 अक्षर)।';

  @override
  String get noCheckout => 'चेकआउट नहीं';

  @override
  String checkOutAt(Object time) {
    return 'बाहर $time';
  }

  @override
  String get enterFiveCharacters => 'कम से कम 5 अक्षर लिखें';

  @override
  String get leads => 'लीड्स';

  @override
  String get followUp => 'फ़ॉलो-अप';

  @override
  String get all => 'सभी';

  @override
  String get deleteEnquiryTitle => 'इनक्वायरी हटाएं?';

  @override
  String deleteEnquiryBody(Object name) {
    return '$name को हटाएं? इसे वापस नहीं लिया जा सकता।';
  }

  @override
  String get updateStatus => 'स्टेटस बदलें';

  @override
  String get addEnquiry => 'इनक्वायरी जोड़ें';

  @override
  String get phone => 'फ़ोन';

  @override
  String get email => 'ईमेल';

  @override
  String get source => 'स्रोत';

  @override
  String get followUpDateOptional => 'फ़ॉलो-अप की तारीख (वैकल्पिक)';

  @override
  String get notes => 'नोट्स';

  @override
  String get saveEnquiry => 'इनक्वायरी सहेजें';

  @override
  String get noLeadsYet => 'अभी कोई लीड नहीं है';

  @override
  String get noLeadsYetBody =>
      'जो लोग जिम आएं या फ़ोन करें, उन्हें यहां जोड़ें। यह सूची बताएगी कि हर दिन किसे फ़ॉलो-अप करना है।';

  @override
  String get reminders => 'रिमाइंडर';

  @override
  String get gymNotFound => 'जिम नहीं मिला';

  @override
  String get push => 'पुश';

  @override
  String get whatsapp => 'WhatsApp';

  @override
  String get invoices => 'इनवॉइस';

  @override
  String get automaticRenewalNudges =>
      'मेंबरशिप खत्म होने से पहले अपने-आप रिमाइंडर';

  @override
  String get on => 'चालू';

  @override
  String get off => 'बंद';

  @override
  String get sendBeforeRenewal => 'रिन्यूअल से पहले भेजें';

  @override
  String get pushReminders => 'पुश रिमाइंडर';

  @override
  String get pushReminderSubtitle => 'मेंबर को ऐप में नोटिफ़िकेशन';

  @override
  String get reminderWindowsHint =>
      'चुने गए दिनों में रिन्यूअल वाले मेंबरों को दिन में एक बार रिमाइंडर भेजा जाता है।';

  @override
  String get whatsappReminders => 'WhatsApp रिमाइंडर';

  @override
  String get whatsappReminderSubtitle => 'मेंबर के WhatsApp पर भेजा गया संदेश';

  @override
  String get oneMessagePerWindow =>
      'हर मेंबर को हर समय खिड़की में एक संदेश। हर संदेश में एक क्रेडिट लगता है।';

  @override
  String get message => 'संदेश';

  @override
  String get preview => 'झलक';

  @override
  String get credits => 'क्रेडिट';

  @override
  String get sendRemindersNow => 'अभी रिमाइंडर भेजें';

  @override
  String get invoiceWhatsappMessages => 'इनवॉइस WhatsApp संदेश';

  @override
  String get invoiceWhatsappSubtitle =>
      'मेंबर को इनवॉइस और पेमेंट रसीद अपने-आप भेजें';

  @override
  String get sameWhatsappCredits => 'रिमाइंडर वाले WhatsApp क्रेडिट ही लगेंगे।';

  @override
  String get freeMonthlyQuota => 'मासिक मुफ़्त कोटा';

  @override
  String get resetsFirstMonth => 'हर महीने की 1 तारीख को रीसेट';

  @override
  String get purchasedCredits => 'खरीदे गए क्रेडिट';

  @override
  String get staffAndRoles => 'स्टाफ और रोल';

  @override
  String get permissions => 'अनुमतियां';

  @override
  String get staffLoadFailed =>
      'स्टाफ लोड नहीं हुआ। दोबारा कोशिश के लिए नीचे खींचें।';

  @override
  String get noStaffMembers => 'अभी कोई स्टाफ नहीं है।';

  @override
  String get inviteStaffMember => 'स्टाफ को आमंत्रित करें';

  @override
  String removeStaffTitle(Object name) {
    return '$name को हटाएं?';
  }

  @override
  String get removeStaffBody =>
      'इस जिम के डैशबोर्ड पर उनका एक्सेस तुरंत बंद हो जाएगा।';

  @override
  String get remove => 'हटाएं';

  @override
  String get staffMemberRemoved => 'स्टाफ हटाया गया';

  @override
  String get roles => 'रोल';

  @override
  String get you => 'आप';

  @override
  String get firstLastNameRequired => 'पहला और आखिरी नाम जरूरी है।';

  @override
  String get inviteStaff => 'स्टाफ को आमंत्रित करें';

  @override
  String get inviteStaffHelp =>
      'उन्हें पासवर्ड बनाने और लॉगिन करने के लिए ईमेल मिलेगा।';

  @override
  String get role => 'रोल';

  @override
  String get sendingInvite => 'आमंत्रण भेजा जा रहा है…';

  @override
  String get sendInvite => 'आमंत्रण भेजें';

  @override
  String get classes => 'बैच';

  @override
  String get deleteBatch => 'बैच हटाएं';

  @override
  String deleteBatchBody(Object name) {
    return '\"$name\" हटाएं? इसके सभी सेशन और नामांकन भी हट जाएंगे। इसे वापस नहीं लिया जा सकता।';
  }

  @override
  String failedToDelete(Object error) {
    return 'हटाना विफल: $error';
  }

  @override
  String get addSession => 'सेशन जोड़ें';

  @override
  String get time => 'समय';

  @override
  String capacityDuration(Object capacity, Object minutes) {
    return 'क्षमता: $capacity · $minutes मिनट';
  }

  @override
  String get hideSessions => 'सेशन छिपाएं';

  @override
  String get viewSessions => 'सेशन देखें';

  @override
  String get noUpcomingSessions => 'कोई आगामी सेशन नहीं';

  @override
  String get noBatchesYet => 'अभी कोई बैच नहीं है';

  @override
  String get addFirstClass => 'शुरू करने के लिए अपना पहला बैच जोड़ें।';

  @override
  String get addBatch => 'बैच जोड़ें';

  @override
  String get editClass => 'बैच बदलें';

  @override
  String get addClass => 'बैच जोड़ें';

  @override
  String get type => 'प्रकार';

  @override
  String get coach => 'कोच';

  @override
  String get capacity => 'क्षमता';

  @override
  String get duration => 'अवधि';

  @override
  String get runsOn => 'किन दिनों पर';

  @override
  String get noDaysSelected =>
      'कोई दिन नहीं चुना — कैलेंडर से हाथ से सेशन जोड़ें।';

  @override
  String get colour => 'रंग';

  @override
  String get descriptionOptional => 'विवरण (वैकल्पिक)';

  @override
  String get saveClass => 'बैच सहेजें';

  @override
  String get removeFromBatch => 'बैच से हटाएं';

  @override
  String removeMemberFromBatch(Object batch, Object name) {
    return '$name को $batch से हटाएं?';
  }

  @override
  String get searchMembers => 'मेंबर खोजें';

  @override
  String get allMembersEnrolled => 'सभी मेंबर पहले से नामांकित हैं।';

  @override
  String get noMembersFound => 'कोई मेंबर नहीं मिला';

  @override
  String get enrolled => 'नामांकित';

  @override
  String get noMembersEnrolled =>
      'अभी कोई मेंबर नामांकित नहीं है — ऊपर से जोड़ें।';

  @override
  String get paymentsDue => 'बाकी पेमेंट';

  @override
  String get allCaughtUp => 'सब पूरा है';

  @override
  String get noOverdueUpcoming => 'अभी कोई बकाया या आगामी पेमेंट नहीं है।';

  @override
  String get nothingDueThatDay => 'उस दिन कुछ बाकी नहीं';

  @override
  String get pickAnotherDay => 'दूसरा दिन चुनें या फ़िल्टर हटाएं।';

  @override
  String get overdue => 'बकाया';

  @override
  String get noOverduePayments => 'कोई बकाया पेमेंट नहीं';

  @override
  String get everyoneUpToDate => 'सभी का पेमेंट पूरा है।';

  @override
  String get oldestFirst => 'सबसे पुराना पहले';

  @override
  String get nothingDueToday => 'आज कुछ बाकी नहीं';

  @override
  String get checkComingNext => 'अगला बाकी पेमेंट देखें।';

  @override
  String get nothingComingUp => 'आगे कुछ नहीं';

  @override
  String get noPaymentsNext30Days => 'अगले 30 दिनों में कोई पेमेंट बाकी नहीं।';

  @override
  String get coming => 'आगामी';

  @override
  String get later => 'बाद में';

  @override
  String get showingOneDay => 'केवल एक दिन दिख रहा है';

  @override
  String get clearDay => 'दिन का फ़िल्टर हटाएं';

  @override
  String get viewExpiredMembers => 'एक्सपायर मेंबर देखें';

  @override
  String get totalOverdue => 'कुल बकाया';

  @override
  String get firstName => 'पहला नाम';

  @override
  String get lastName => 'आखिरी नाम';

  @override
  String get initialStatus => 'शुरुआती स्टेटस';

  @override
  String teamMembersCount(num count) {
    return '$count टीम सदस्य';
  }

  @override
  String inviteSentTo(Object email) {
    return '$email पर आमंत्रण भेजा गया';
  }

  @override
  String get failedSendInvite => 'आमंत्रण भेजना विफल';

  @override
  String starterStaffLimit(Object count) {
    return 'Starter में $count लॉगिन मिलता है। स्टाफ जोड़ने के लिए Pro पर अपग्रेड करें।';
  }

  @override
  String get today => 'आज';

  @override
  String get tomorrow => 'कल';

  @override
  String get filterByPlan => 'प्लान से फ़िल्टर';

  @override
  String get lapsingWithin => 'इतने दिन में खत्म';

  @override
  String get joinedWithin => 'इतने दिन में जुड़े';

  @override
  String get expiringSoon => 'जल्द खत्म होने वाले';

  @override
  String get searchMemberHint => 'नाम, मोबाइल या मेंबर आईडी';

  @override
  String get stepMember => '1 · मेंबर';

  @override
  String get stepMembership => '2 · मेंबरशिप';

  @override
  String get stepPayment => '3 · पेमेंट';

  @override
  String get fullName => 'पूरा नाम';

  @override
  String get mobileNumber => 'मोबाइल नंबर';

  @override
  String get batch => 'बैच';

  @override
  String get memberId => 'मेंबर आईडी';

  @override
  String get discount => 'छूट';

  @override
  String get amountCollected => 'ली गई राशि';

  @override
  String get emergencyContact => 'आपातकालीन संपर्क';

  @override
  String get name => 'नाम';

  @override
  String get number => 'नंबर';

  @override
  String get emergencyNameHint => 'जैसे रमेश (पिता)';

  @override
  String get contact => 'संपर्क';

  @override
  String get biometricDeviceId => 'बायोमेट्रिक डिवाइस आईडी';

  @override
  String get enrolledBatches => 'नामांकित बैच';

  @override
  String get recentCheckIns => 'हाल के चेक-इन';

  @override
  String get recurringDiscount => 'हर बार मिलने वाली छूट';

  @override
  String get editRecurringDiscountTitle => 'हर बार की छूट बदलें';

  @override
  String get discountAmount => 'छूट की राशि';

  @override
  String get due => 'बाकी';

  @override
  String get dueTodayLabel => 'आज बाकी';

  @override
  String daysOverdue(Object days) {
    return '$days दिन बकाया';
  }

  @override
  String upcomingInDays(Object days) {
    return '$days दिन में आने वाला';
  }

  @override
  String get clearDates => 'तारीखें हटाएं';

  @override
  String get partlyPaid => 'कुछ भुगतान हुआ';

  @override
  String get method => 'तरीका';

  @override
  String get notesOptional => 'नोट्स (वैकल्पिक)';

  @override
  String get admissionFeeOptional => 'एडमिशन फ़ीस (वैकल्पिक)';

  @override
  String get discountOptional => 'छूट (वैकल्पिक)';

  @override
  String get dueDateOptional => 'बाकी तारीख (वैकल्पिक)';

  @override
  String get deletePlanTitle => 'प्लान हटाएं?';

  @override
  String get planName => 'प्लान का नाम';

  @override
  String get price => 'कीमत';

  @override
  String get monthly => 'मासिक';

  @override
  String get quarterly => 'तिमाही';

  @override
  String get sixMonths => '6 महीने';

  @override
  String get yearly => 'सालाना';

  @override
  String get custom => 'कस्टम…';

  @override
  String get durationMonths => 'अवधि (महीने)';

  @override
  String get maxClassesOptional => 'अधिकतम क्लास (खाली = असीमित)';

  @override
  String get includes => 'शामिल';

  @override
  String get addFeature => 'सुविधा जोड़ें';

  @override
  String get savePlan => 'प्लान सहेजें';

  @override
  String get language => 'भाषा';

  @override
  String get tryNewDesignTitle => 'नया डिज़ाइन आज़माएं?';

  @override
  String get switchBackClassicTitle => 'पुराने डिज़ाइन पर लौटें?';

  @override
  String get actionSwitch => 'बदलें';

  @override
  String get switchBack => 'वापस बदलें';

  @override
  String get designSwitchFailed => 'डिज़ाइन नहीं बदला। दोबारा कोशिश करें।';

  @override
  String get phoneOptional => 'फ़ोन (वैकल्पिक)';

  @override
  String get saveProfile => 'प्रोफ़ाइल सहेजें';

  @override
  String get newPassword => 'नया पासवर्ड';

  @override
  String get confirmNewPassword => 'नया पासवर्ड दोबारा';

  @override
  String get updatePassword => 'पासवर्ड बदलें';

  @override
  String get done => 'हो गया';

  @override
  String get gymName => 'जिम का नाम';

  @override
  String get addressOptional => 'पता (वैकल्पिक)';

  @override
  String get websiteOptional => 'वेबसाइट यूआरएल (वैकल्पिक)';

  @override
  String get currency => 'मुद्रा';

  @override
  String get saveDetails => 'जानकारी सहेजें';

  @override
  String get payments => 'पेमेंट';

  @override
  String get keyId => 'की आईडी';

  @override
  String get keySecret => 'की सीक्रेट';

  @override
  String get enterToUpdate => 'बदलने के लिए भरें';

  @override
  String get updateKeys => 'की बदलें';

  @override
  String get connectRazorpay => 'Razorpay जोड़ें';

  @override
  String get viewPastTickets => 'पुराने टिकट देखें';

  @override
  String get supportTopic => 'यह किस बारे में है?';

  @override
  String get title => 'शीर्षक';

  @override
  String get shortIssueSummary => 'समस्या का छोटा सार';

  @override
  String get detailsOptional => 'विवरण (वैकल्पिक)';

  @override
  String get detailsHint => 'ऐसी कोई भी जानकारी जो समस्या समझने में मदद करे';

  @override
  String get submitTicket => 'टिकट भेजें';

  @override
  String get myTickets => 'मेरे टिकट';

  @override
  String get regenerateLinkTitle => 'लिंक दोबारा बनाएं?';

  @override
  String get regenerate => 'दोबारा बनाएं';

  @override
  String get selfRegistrationLink => 'खुद रजिस्ट्रेशन लिंक';

  @override
  String get shareLink => 'लिंक शेयर करें';

  @override
  String get regenerateLink => 'लिंक दोबारा बनाएं';

  @override
  String get biometricDevice => 'बायोमेट्रिक डिवाइस';

  @override
  String get pair => 'पेयर करें';

  @override
  String get viewSetupGuide => 'पूरी सेटअप गाइड देखें';

  @override
  String get contactWhatsapp => 'WhatsApp पर हमसे संपर्क करें';

  @override
  String get seeProPlans => 'Pro प्लान देखें';

  @override
  String get typeDeleteConfirm => 'पुष्टि के लिए DELETE लिखें';

  @override
  String galleryOpenFailed(Object error) {
    return 'गैलरी नहीं खुली: $error';
  }

  @override
  String get razorpayConnected => 'Razorpay जुड़ गया';

  @override
  String get razorpayDisconnected => 'Razorpay हटा दिया गया';

  @override
  String ticketsLoadFailed(Object error) {
    return 'टिकट लोड नहीं हुए: $error';
  }

  @override
  String copiedLabel(Object label) {
    return '$label कॉपी हुआ';
  }

  @override
  String amountRequiredWithCurrency(Object currency) {
    return 'राशि ($currency) *';
  }

  @override
  String get error => 'गलती';

  @override
  String get gymQr => 'जिम क्यूआर';

  @override
  String get checkIn => 'चेक-इन';

  @override
  String get callTooltip => 'फ़ोन करें';

  @override
  String get checkoutStartFailed => 'चेकआउट शुरू नहीं हुआ। दोबारा कोशिश करें।';

  @override
  String get packUnavailable => 'यह पैक अभी उपलब्ध नहीं है।';

  @override
  String get purchaseSuccessful => 'खरीद सफ़ल — क्रेडिट जल्द दिखेंगे।';

  @override
  String purchaseFailed(Object error) {
    return 'खरीद विफल: $error';
  }

  @override
  String sendFailed(Object error) {
    return 'भेजना विफल: $error';
  }

  @override
  String get className => 'बैच का नाम';

  @override
  String removeFailed(Object error) {
    return 'हटाना विफल: $error';
  }

  @override
  String get expiring => 'खत्म होने वाले';

  @override
  String get joined => 'नए जुड़े';

  @override
  String get expired => 'खत्म';

  @override
  String get active => 'चालू';

  @override
  String get onHold => 'रोके गए';

  @override
  String get statusNew => 'नया';

  @override
  String get statusContacted => 'संपर्क हुआ';

  @override
  String get statusTrial => 'ट्रायल';

  @override
  String get statusConverted => 'मेंबर बना';

  @override
  String get statusLost => 'छूट गया';

  @override
  String get sourceManual => 'हाथ से';

  @override
  String get sourceWebsite => 'वेबसाइट';

  @override
  String get sourceReferral => 'रेफ़रल';

  @override
  String get sourceWalkIn => 'जिम पर आया';

  @override
  String get sourceSocial => 'सोशल मीडिया';

  @override
  String get managerAccessHint => 'मेंबर, बैच, बिलिंग और संचार';

  @override
  String get trainerAccessHint => 'अपने बैच और समय, चेक-इन, अटेंडेंस';

  @override
  String get staffAccessHint => 'मेंबर और चेक-इन का बुनियादी एक्सेस';

  @override
  String daysLate(Object days) {
    return '$days दिन देर';
  }

  @override
  String inDays(Object days) {
    return '$days दिन में';
  }

  @override
  String get chooseLanguage => 'अपनी भाषा चुनें';

  @override
  String get chooseLanguageSubtitle =>
      'GymCRM को किस भाषा में इस्तेमाल करना है, वह चुनें।';

  @override
  String get continueLabel => 'आगे बढ़ें';

  @override
  String get languageChangeLater => 'आप इसे बाद में सेटिंग्स से बदल सकते हैं।';

  @override
  String get welcomeGymcrm => 'GymCRM में आपका स्वागत है।';

  @override
  String get runAGym => 'मैं जिम चलाता हूं';

  @override
  String get gymMember => 'मैं जिम मेंबर हूं';

  @override
  String get needHelp => 'मदद चाहिए? ';

  @override
  String get contactUs => 'हमसे संपर्क करें';

  @override
  String get gymTeams => 'जिम टीम के लिए';

  @override
  String get runFloorHeadline => 'जिम चलाएं।\nहर दिन संभालें।';

  @override
  String get gymOwner => 'जिम मालिक';

  @override
  String get welcomeBack => 'फिर से स्वागत है';

  @override
  String get loginSubtitle => 'आज का जिम संभालने के लिए लॉगिन करें।';

  @override
  String get password => 'पासवर्ड';

  @override
  String get emailRequired => 'ईमेल जरूरी है';

  @override
  String get validEmail => 'सही ईमेल डालें';

  @override
  String get passwordRequired => 'पासवर्ड जरूरी है';

  @override
  String get forgotPassword => 'पासवर्ड भूल गए?';

  @override
  String get login => 'लॉगिन करें';

  @override
  String get loggingIn => 'लॉगिन हो रहा है…';

  @override
  String get or => 'या';

  @override
  String get newGym => 'नया जिम? ';

  @override
  String get createAccount => 'अकाउंट बनाएं';

  @override
  String get secureRecovery => 'सुरक्षित रिकवरी';

  @override
  String get recoveryHeadline => 'वापस आएं।\nबिना चिंता।';

  @override
  String get resetPasswordTitle => 'अपना पासवर्ड रीसेट करें';

  @override
  String get resetPasswordHelp =>
      'जिस ईमेल से साइनअप किया था, वह डालें। हम रीसेट लिंक भेजेंगे।';

  @override
  String get sendResetLink => 'रीसेट लिंक भेजें';

  @override
  String get checkYourEmailLabel => 'अपना ईमेल देखें';

  @override
  String get resetHeadline => 'एक टैप में\nरीसेट।';

  @override
  String get linkSent => 'लिंक भेजा गया';

  @override
  String get checkEmailPrefix => 'यह ईमेल देखें: ';

  @override
  String get resetLinkExpiry =>
      ' और रीसेट लिंक खोलें। यह एक घंटे में खत्म हो जाएगा।';

  @override
  String get checkSpam => 'इनबॉक्स में नहीं? स्पैम देखें';

  @override
  String sendAgainIn(Object seconds) {
    return ', या $seconds सेकंड में दोबारा भेजें।';
  }

  @override
  String get sendAgain => 'दोबारा भेजें';

  @override
  String get backToLogin => 'लॉगिन पर वापस जाएं';

  @override
  String get back => '← वापस';

  @override
  String get buildWithGymcrm => 'GymCRM के साथ बनाएं';

  @override
  String get gymOnePlace => 'आपका जिम।\nएक जगह।';

  @override
  String get createYourGym => 'अपना जिम बनाएं';

  @override
  String get oneMinute => 'लगभग एक मिनट लगेगा।';

  @override
  String get signupGoogle => 'Google से साइनअप करें';

  @override
  String get gymNameRequired => 'जिम का नाम जरूरी है';

  @override
  String get countryCurrency => 'देश और मुद्रा';

  @override
  String get yourName => 'आपका नाम';

  @override
  String get nameRequired => 'नाम जरूरी है';

  @override
  String get mobileOptional => 'मोबाइल नंबर (वैकल्पिक)';

  @override
  String get validMobile => 'सही मोबाइल नंबर डालें';

  @override
  String get tapFlagCountry => 'देश बदलने के लिए झंडे पर टैप करें';

  @override
  String get minEightCharacters => 'कम से कम 8 अक्षर';

  @override
  String get passwordEightCharacters =>
      'पासवर्ड में कम से कम 8 अक्षर होने चाहिए';

  @override
  String get alreadyGymcrm => 'पहले से GymCRM पर हैं? ';

  @override
  String get changeEmail => '← ईमेल बदलें';

  @override
  String get verifyEmailLabel => 'ईमेल की पुष्टि करें';

  @override
  String get almostThere => 'बस थोड़ा और।';

  @override
  String get checkYourEmail => 'अपना ईमेल देखें';

  @override
  String get sentSixDigitCode => 'हमने 6 अंकों का कोड भेजा है:\n';

  @override
  String get verify => 'पुष्टि करें';

  @override
  String resendCodeIn(Object seconds) {
    return '$seconds सेकंड में कोड दोबारा भेजें';
  }

  @override
  String get resendCode => 'कोड दोबारा भेजें';

  @override
  String get codeResentEmail => 'कोड दोबारा भेजा गया — ईमेल देखें।';

  @override
  String get weak => 'कमजोर';

  @override
  String get fair => 'ठीक';

  @override
  String get strong => 'मजबूत';

  @override
  String get agreeTo => 'मैं सहमत हूं: ';

  @override
  String get and => ' और ';

  @override
  String get acceptTermsError =>
      'आगे बढ़ने के लिए सेवा की शर्तें और प्राइवेसी पॉलिसी स्वीकार करें।';

  @override
  String get continueGoogle => 'Google से आगे बढ़ें';

  @override
  String get mobileAccess => 'मोबाइल से प्रवेश';

  @override
  String get mobileAccessHeadline => 'एक कोड।\nऔर आप अंदर।';

  @override
  String get loginWithMobile => 'मोबाइल से लॉगिन करें';

  @override
  String get mobileOtpHelp => 'हम आपको एक बार इस्तेमाल होने वाला कोड भेजेंगे।';

  @override
  String get sendCode => 'कोड भेजें';

  @override
  String get otpSendFailed => 'OTP नहीं भेजा जा सका। दोबारा कोशिश करें।';

  @override
  String get codeResentSms => 'कोड SMS से दोबारा भेजा गया।';

  @override
  String get resendFailed => 'कोड दोबारा नहीं भेजा जा सका। फिर कोशिश करें।';

  @override
  String get incorrectCode => 'कोड सही नहीं है। दोबारा कोशिश करें।';

  @override
  String get verificationFailed => 'पुष्टि नहीं हो सकी। दोबारा कोशिश करें।';

  @override
  String get verifyYourNumber => 'अपने नंबर की पुष्टि करें';

  @override
  String get checkMessages => 'अपने मैसेज देखें।';

  @override
  String get enterVerificationCode => 'पुष्टि कोड डालें';

  @override
  String get changeNumber => 'नंबर बदलें';

  @override
  String get setUpYourGym => 'अपना जिम सेट करें';

  @override
  String setupStep(int step) {
    return '4 में से चरण $step';
  }

  @override
  String get tellUsAboutGym => 'अपने जिम के बारे में बताएं';

  @override
  String get membersWillSee => 'मेंबर को यही जानकारी दिखाई देगी।';

  @override
  String get createGym => 'जिम बनाएं';

  @override
  String get freeTrialNoCard =>
      '3 दिन का मुफ्त ट्रायल · क्रेडिट कार्ड जरूरी नहीं';

  @override
  String get optionalLabel => '— वैकल्पिक';

  @override
  String get monthlyMembership => 'मासिक मेंबरशिप';

  @override
  String get planNameRequired => 'प्लान का नाम जरूरी है।';

  @override
  String get planPriceRequired => 'इस प्लान की कीमत डालें।';

  @override
  String get planCreateFailed => 'प्लान नहीं बन सका। दोबारा कोशिश करें।';

  @override
  String get createFirstPlan => 'अपना पहला मेंबरशिप प्लान बनाएं';

  @override
  String get createFirstPlanHelp => 'वह प्लान सेट करें जिसे आपके मेंबर लेंगे।';

  @override
  String get billingCycle => 'बिलिंग अवधि';

  @override
  String get whatsIncluded => 'क्या शामिल है';

  @override
  String get createPlanContinue => 'प्लान बनाकर आगे बढ़ें';

  @override
  String get creatingPlan => 'प्लान बन रहा है…';

  @override
  String get firstNameRequired => 'पहला नाम जरूरी है।';

  @override
  String get memberAddFailed => 'यह मेंबर नहीं जुड़ सका। दोबारा कोशिश करें।';

  @override
  String get addFirstMember => 'अपना पहला मेंबर जोड़ें';

  @override
  String get addFirstMemberHelp => 'आप बाद में और मेंबर जोड़ सकते हैं।';

  @override
  String get plan => 'प्लान';

  @override
  String get moreMemberDetails => 'और जानकारी — मेंबर आईडी, भुगतान राशि, नोट्स';

  @override
  String get amountPaid => 'भुगतान राशि';

  @override
  String get notesHint => 'याद रखने योग्य कोई बात';

  @override
  String get addingMember => 'मेंबर जोड़ा जा रहा है…';

  @override
  String get skipForNow => 'अभी छोड़ें';

  @override
  String get yourGym => 'आपका जिम';

  @override
  String get gymReady => 'आपका जिम तैयार है';

  @override
  String get gymCreated => 'जिम बन गया';

  @override
  String get firstPlanCreated => 'पहला प्लान बन गया';

  @override
  String get firstMemberAdded => 'पहला मेंबर जुड़ गया';

  @override
  String get goToDashboard => 'डैशबोर्ड पर जाएं';

  @override
  String get setupReadyHelp =>
      'आप डैशबोर्ड से और प्लान, मेंबर और स्टाफ जोड़ सकते हैं।';

  @override
  String get addMenuSubtitle => 'आप क्या जोड़ना चाहते हैं?';

  @override
  String get addMenuMember => 'मेंबर';

  @override
  String get addMenuMemberHint => 'नया एडमिशन, प्लान और पहला पेमेंट';

  @override
  String get addMenuInvoice => 'इनवॉइस';

  @override
  String get addMenuInvoiceHint => 'मेंबर को प्लान या सर्विस का बिल दें';

  @override
  String get addMenuPlan => 'प्लान';

  @override
  String get addMenuPlanHint => 'मंथली, क्वार्टरली या ईयरली मेंबरशिप';

  @override
  String get addMenuLead => 'लीड';

  @override
  String get addMenuLeadHint => 'वॉक-इन या पूछताछ, जिसका फ़ॉलो-अप करना है';

  @override
  String get addMenuBatch => 'बैच';

  @override
  String get addMenuBatchHint => 'सुबह, शाम या तय समय वाली क्लास';

  @override
  String get addMenuStaff => 'स्टाफ';

  @override
  String get addMenuStaffHint => 'ट्रेनर, मैनेजर या फ़्रंट डेस्क को जोड़ें';

  @override
  String get addMenuExpense => 'खर्चा';

  @override
  String get addMenuExpenseHint => 'किराया, सैलरी, मशीनें, बिजली-पानी';
}
