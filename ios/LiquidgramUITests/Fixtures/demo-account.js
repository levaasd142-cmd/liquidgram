// Seeds a demo account for the UI tests, so the web app shows its main screen with chats and messages. The tests
// inject it at document start through `LIQUIDGRAM_TEST_USER_SCRIPT`, before the app's scripts and after
// `offline-api.js`, which keeps the session offline. It writes what a signed-in session leaves in `localStorage`
// (`account1` and the cached global state in `tt-global-state`, with message dates relative to now) and API keys of
// the valid form, which the web app needs before it shows the main screen; offline, the keys are never used.
// The cached state has only the sections the chats need. `migrateCache` logs a TypeError for the missing ones, such
// as `appConfig`, and `readCache` takes them from the initial state. The photo in the chat with Катя Дизайн is drawn
// on a canvas and stored as its `blobUrl`, the way the web app keeps a photo it has just sent, so the media viewer
// opens it without a download.
(() => {
  'use strict';

  const SEEDED_KEY = 'liquidgram-test-demo-seeded';
  const ACCOUNT_KEY = 'account1';
  const GLOBAL_STATE_KEY = 'tt-global-state';
  const API_CREDENTIALS_KEY = 'lg-api-credentials';
  const API_CREDENTIALS = { apiId: 1, apiHash: '0123456789abcdef0123456789abcdef' };
  const DC_ID = 2;
  const CACHE_VERSION = 8;
  const MAIN_THREAD_ID = -1;
  const SECONDS_IN_MINUTE = 60;
  const ONLINE_EXPIRES_SECONDS = 600;
  const OFFLINE_SINCE_SECONDS = 3600;
  const ACCOUNT_TTL_DAYS = 365;
  const ME = '100000';
  const PHOTO_SIZE = { width: 320, height: 240 };
  const PHOTO_ID = '5000000001';
  const PHOTO_SIZE_TYPE = 'x';
  const PHOTO_QUALITY = 0.8;

  seedOncePerSession();

  // A page reload keeps the session storage, so the state the app has changed since the first load stays
  function seedOncePerSession() {
    try {
      if (sessionStorage.getItem(SEEDED_KEY)) return;

      localStorage.setItem(ACCOUNT_KEY, JSON.stringify({ dcId: DC_ID, userId: ME }));
      localStorage.setItem(GLOBAL_STATE_KEY, JSON.stringify(buildGlobalState()));
      localStorage.setItem(API_CREDENTIALS_KEY, JSON.stringify(API_CREDENTIALS));
      sessionStorage.setItem(SEEDED_KEY, '1');
    } catch (err) {
      // The self-test and the screenshots show the missing account; the page must not break here
    }
  }

  function buildGlobalState() {
    const now = Math.floor(Date.now() / 1000);
    const users = {};
    const statuses = {};
    const chats = {};
    const messagesByChatId = {};
    const lastMessageIds = {};
    const listIds = [];

    function addUser(id, firstName, lastName, color, isOnline) {
      users[id] = {
        id,
        isMin: false,
        type: 'userTypeRegular',
        firstName,
        lastName,
        phoneNumber: '',
        color: { color },
        isContact: true,
        isSelf: id === ME ? true : undefined,
      };
      statuses[id] = isOnline
        ? { type: 'userStatusOnline', expires: now + ONLINE_EXPIRES_SECONDS }
        : { type: 'userStatusOffline', wasOnline: now - OFFLINE_SINCE_SECONDS };
    }

    function addChat(id, chat) {
      chats[id] = Object.assign({ id }, chat);
      listIds.push(id);
    }

    // `ago` and the other times are minutes before now
    function addMessages(chatId, list, readState) {
      const { unreadCount = 0 } = readState || {};
      const byId = {};
      list.forEach((item, index) => {
        const id = item.id || index + 1;
        const date = now - (item.ago || 0) * SECONDS_IN_MINUTE;
        byId[id] = {
          id,
          chatId,
          date,
          isOutgoing: Boolean(item.out),
          senderId: item.out ? ME : (item.from || chatId),
          content: {
            text: item.text ? { text: item.text, entities: [] } : undefined,
            photo: item.hasPhoto ? buildPhoto(date) : undefined,
          },
          viewsCount: item.views,
          isEdited: item.editedAgo ? true : undefined,
          editDate: item.editedAgo ? now - item.editedAgo * SECONDS_IN_MINUTE : undefined,
          deletedDate: item.deletedAgo ? now - item.deletedAgo * SECONDS_IN_MINUTE : undefined,
        };
      });
      const ids = Object.keys(byId).map(Number).sort((a, b) => a - b);
      const lastId = ids[ids.length - 1];
      lastMessageIds[chatId] = lastId;
      messagesByChatId[chatId] = {
        byId,
        threadsById: {
          [MAIN_THREAD_ID]: {
            localState: { listedIds: ids, lastViewportIds: ids },
            threadInfo: {
              isCommentsInfo: false, chatId, threadId: MAIN_THREAD_ID, lastMessageId: lastId,
            },
            readState: {
              unreadCount,
              lastReadInboxMessageId: lastId - unreadCount,
              lastReadOutboxMessageId: lastId,
            },
          },
        },
        ephemeralById: {},
        anchoredById: {},
        summaryById: {},
      };
    }

    addUser(ME, 'Бро', '', 1, true);
    addUser('100101', 'Аня', 'Смирнова', 5, true);
    addUser('100102', 'Макс', 'Орлов', 2, false);
    addUser('100103', 'Лёха', '', 0, true);
    addUser('100104', 'Мама', '', 3, false);
    addUser('100105', 'Дима', 'Код', 4, false);
    addUser('100106', 'Катя', 'Дизайн', 6, true);

    addChat('100101', { type: 'chatTypePrivate', title: 'Аня Смирнова' });
    addMessages('100101', [
      { id: 1, ago: 1500, text: 'Скинь фотки с выходных 📸' },
      { id: 2, ago: 1495, out: true, text: 'Щас, только с телефона перекину' },
      { id: 3, ago: 1490, text: 'Жду-жду' },
      {
        id: 4,
        ago: 1480,
        out: true,
        text: 'Кстати, ты пробовала новый Liquid Glass в iOS 26? Всё будто из жидкого стекла 💧',
      },
      { id: 5, ago: 1470, text: 'Да! Особенно таббар внизу, он прям переливается' },
      { id: 6, ago: 1465, out: true, text: 'Хочу такое на компе в телеге' },
      { id: 7, ago: 1460, text: 'Сделай сам, ты же умный 😄' },
      { id: 8, ago: 1450, out: true, text: 'Вызов принят 😎' },
      { id: 9, ago: 52, text: 'Привет! Ты видел новый айос? 😍' },
      { id: 10, ago: 51, out: true, text: 'Да, этот Liquid Glass просто бомба' },
      { id: 11, ago: 50, text: 'Хочу такое же в телеге', editedAgo: 49 },
      {
        id: 12,
        ago: 48,
        out: true,
        text: 'Смотри что я собрал 👀 Liquidgram — свой клиент со стеклом и режимом призрака',
      },
      { id: 13, ago: 47, text: 'Чё серьёзно?? Скинь ссылку' },
      { id: 14, ago: 46, text: 'Ой, это я не тебе написала 🙈', deletedAgo: 45 },
      { id: 15, ago: 44, out: true, text: 'Поздно, я всё видел 😏 антиудаление работает' },
      { id: 16, ago: 12, text: 'Ахахах ладно, ты победил' },
      { id: 17, ago: 11, text: 'Во сколько завтра встречаемся?' },
      { id: 18, ago: 3, out: true, text: 'Давай в 19:00 у кофейни на Патриках ☕️' },
      { id: 19, ago: 1, text: 'Договорились! До завтра 💙' },
    ], { unreadCount: 1 });

    addChat('-1001000000001', {
      type: 'chatTypeSuperGroup', title: 'Бразы 🔥', membersCount: 24, isOwner: true,
    });
    addMessages('-1001000000001', [
      { ago: 95, from: '100102', text: 'Пацаны, кто на футбол в субботу?' },
      { ago: 93, from: '100103', text: 'Я в деле ⚽️' },
      { ago: 90, out: true, text: '+ буду' },
      { ago: 30, from: '100105', text: 'Залил новый билд, гляньте кто-нибудь' },
      { ago: 28, from: '100102', text: 'Глянул — стекло выглядит как на айфоне, респект 🫡' },
      { ago: 6, from: '100103', text: 'Кто сегодня в чат-рум после 22?' },
    ], { unreadCount: 4 });

    addChat('-1001000000002', {
      type: 'chatTypeChannel', title: 'iOS 26 Design', membersCount: 128400, isVerified: true,
    });
    addMessages('-1001000000002', [
      {
        ago: 300, text: 'Liquid Glass — новый материал Apple: он преломляет и отражает всё, что под ним.', views: 48200,
      },
      { ago: 120, text: 'Главные принципы: прозрачность, глубина и живая реакция на движение 💧', views: 39100 },
      { ago: 20, text: 'Собрали 15 приложений, которые уже обновили дизайн под iOS 26 👇', views: 12800 },
    ], { unreadCount: 2 });

    addChat('100106', { type: 'chatTypePrivate', title: 'Катя Дизайн' });
    addMessages('100106', [
      { ago: 180, text: 'Макет готов, посмотри в фигме' },
      { ago: 179, hasPhoto: true, text: 'Превью главного экрана' },
      { ago: 170, out: true, text: 'Огонь 🔥 Только кнопку сделай стеклянной' },
      { ago: 160, text: 'Уже 😎' },
    ]);

    addChat('100104', { type: 'chatTypePrivate', title: 'Мама' });
    addMessages('100104', [
      { ago: 400, text: 'Сынок, ты покушал?' },
      { ago: 390, out: true, text: 'Да, мам 🙂' },
      { ago: 240, text: 'Позвони вечером ❤️' },
    ]);

    addChat('100102', { type: 'chatTypePrivate', title: 'Макс Орлов' });
    addMessages('100102', [
      { ago: 1500, out: true, text: 'Скинь презентацию' },
      { ago: 1490, text: 'Лови, там 40 слайдов' },
    ]);

    addChat('100105', { type: 'chatTypePrivate', title: 'Дима Код' });
    addMessages('100105', [
      { ago: 2000, text: 'npm run build упал, глянь логи' },
      { ago: 1990, out: true, text: 'Поправил, перезапусти' },
    ]);

    addChat(ME, { type: 'chatTypePrivate', title: 'Избранное' });
    addMessages(ME, [
      { ago: 3000, out: true, text: 'Идеи для Liquidgram: стекло, призрак, антиудаление ✅' },
    ]);

    const peerColors = ['#D45246', '#F68136', '#6C61DF', '#46BA43', '#5CAFFA', '#408ACF', '#D95574'];

    return {
      cacheVersion: CACHE_VERSION,
      peerColors: {
        general: peerColors.reduce((result, color, index) => {
          result[index] = { colors: [color] };
          return result;
        }, {}),
        profile: {},
      },
      currentUserId: ME,
      settings: {
        byKey: {},
        privacy: {},
        botVerificationShownPeerIds: [],
        accountDaysTtl: ACCOUNT_TTL_DAYS,
      },
      sharedState: { settings: { language: 'en' } },
      contactList: { userIds: Object.keys(users).filter((id) => id !== ME) },
      users: {
        byId: users,
        statusesById: statuses,
        fullInfoById: {},
        previewMediaByBotId: {},
        commonChatsById: {},
        savedMusicByPeerId: {},
        botAppPermissionsById: {},
      },
      chats: {
        listIds: { active: listIds },
        isFullyLoaded: { active: true },
        orderedPinnedIds: { active: ['100101'] },
        totalCount: { all: listIds.length },
        lastMessageIds: { all: lastMessageIds },
        byId: chats,
        fullInfoById: {},
        similarChannelsById: {},
        similarBotsById: {},
        topicsInfoById: {},
        notifyExceptionById: {},
        loadingParameters: { active: {}, archived: {}, saved: {} },
      },
      messages: {
        byChatId: messagesByChatId,
        sponsoredByChatId: {},
        pollById: {},
        webPageById: {},
        playbackByChatId: {},
      },
      chatFolders: {
        orderedIds: [0, 1, 2, 3],
        byId: {
          1: {
            id: 1,
            title: { text: 'Личное' },
            contacts: true,
            nonContacts: true,
            includedChatIds: [],
            excludedChatIds: [],
          },
          2: {
            id: 2, title: { text: 'Группы' }, groups: true, includedChatIds: [], excludedChatIds: [],
          },
          3: {
            id: 3, title: { text: 'Каналы' }, channels: true, includedChatIds: [], excludedChatIds: [],
          },
        },
        invites: {},
      },
      liquid: {
        deletedMessagesByChatId: {},
        editHistoryByChatId: {
          100101: {
            11: [{ date: now - 50 * SECONDS_IN_MINUTE, text: { text: 'Хочу такое в телеге', entities: [] } }],
          },
        },
      },
    };
  }

  // A glassy mock-up of a chat screen as a JPEG data URI
  function buildPhoto(date) {
    const canvas = document.createElement('canvas');
    canvas.width = PHOTO_SIZE.width;
    canvas.height = PHOTO_SIZE.height;
    const context = canvas.getContext('2d');
    const gradient = context.createLinearGradient(0, 0, PHOTO_SIZE.width, PHOTO_SIZE.height);
    gradient.addColorStop(0, '#B9B4F5');
    gradient.addColorStop(1, '#5CAFFA');
    context.fillStyle = gradient;
    context.fillRect(0, 0, PHOTO_SIZE.width, PHOTO_SIZE.height);
    context.fillStyle = 'rgba(255, 255, 255, 0.55)';
    [[24, 24, 272, 36], [24, 76, 180, 28], [116, 116, 180, 28], [24, 180, 272, 36]].forEach(([x, y, w, h]) => {
      context.fillRect(x, y, w, h);
    });
    const dataUri = canvas.toDataURL('image/jpeg', PHOTO_QUALITY);
    return {
      mediaType: 'photo',
      id: PHOTO_ID,
      date,
      thumbnail: { width: PHOTO_SIZE.width, height: PHOTO_SIZE.height, dataUri },
      sizes: [{ width: PHOTO_SIZE.width, height: PHOTO_SIZE.height, type: PHOTO_SIZE_TYPE }],
      blobUrl: dataUri,
    };
  }
})();
