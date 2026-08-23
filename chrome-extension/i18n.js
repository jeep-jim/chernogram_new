export const LANGS = ['en', 'ru', 'de', 'fr', 'es'];

const T = {
  en: {
    brandTag:'private chats and calls', heroTitle:'Connection without borders', heroText:'Private messages and browser calls — fast, quiet and without ads.', newChat:'New chat', emptyHelp:'Create an invitation to start a private conversation.', contactsHelp:'People you connect with are saved here on this device.', noContacts:'No contacts yet', changeAvatar:'Change avatar', privacyMask:'Privacy mask', privacyMaskHelp:'Hide names and message previews in the interface.', appearance:'Appearance', lightTheme:'Light theme', darkTheme:'Dark theme', themeHelp:'Switch between the light and dark VeilTalk interface.', calling:'Calling…', avatarImageOnly:'Choose a PNG, JPEG or WebP image.', avatarTooLarge:'Avatar image must be under 5 MB.',
    chats:'Chats', contacts:'Contacts', settings:'Settings', newContact:'New contact', createInvite:'Create invite',
    pasteInvite:'Paste invite', copy:'Copy', copied:'Copied', pending:'Waiting for contact', connected:'Connected', offline:'Offline',
    message:'Message', send:'Send', call:'Voice call', video:'Video call', attach:'File', noChats:'No conversations yet',
    profile:'Profile', displayName:'Display name', language:'Language', privacy:'Privacy', plan:'Plan', free:'Free', pro:'Pro',
    freePlan:'Unlimited text chat · 10 call/video minutes per day · 25 MB files', proPlan:'Unlimited calls/video · HD · screen sharing · up to 1 GB P2P files',
    upgrade:'Upgrade to Pro — $9.99/month', activate:'Activate license', licenseKey:'License key', billingSoon:'Live checkout configuration is required before release.',
    remaining:'Free call time today', minutes:'min', incomingCall:'Incoming call', answer:'Answer', decline:'Decline', hangup:'Hang up',
    mic:'Microphone', camera:'Camera', shareScreen:'Share screen', directP2P:'Direct WebRTC media', relayNote:'Messages/signaling use an encrypted public relay; media is direct when possible.',
    inviteHelp:'Send this invite code to one person. It contains a random room secret and your inbox address.',
    pasteHelp:'Paste the VeilTalk invite code you received.', save:'Save', delete:'Delete', version:'Version',
    chromeOpen:'VeilTalk stays reachable while Chrome is running. Pin the side panel for the best calling experience.',
    callLimit:'Free call limit reached for today. Chat still works.', contactLimit:'Free contact limit reached.', invalidInvite:'Invalid invite.',
    notReady:'Contact has not completed pairing yet.', fileTooLarge:'File is larger than your plan allows.', fileSent:'File sent', download:'Download',
    search:'Search contacts', today:'Today', network:'Network', online:'Online', reconnecting:'Reconnecting', licenseValid:'Pro active', licenseInvalid:'License is not valid',
    subscription:'Subscription', directOnly:'No owned servers', about:'About', localData:'Chat history, contacts and profile are stored locally in Chrome.',
    needTurn:'Some corporate or restrictive networks may require a TURN relay; this MVP uses public STUN only.'
  },
  ru: {
    brandTag:'приватные чаты и звонки', heroTitle:'Связь без границ', heroText:'Приватные сообщения и звонки прямо в браузере — быстро, тихо и без рекламы.', newChat:'Новый чат', emptyHelp:'Создай приглашение, чтобы начать приватный диалог.', contactsHelp:'Здесь сохраняются люди, с которыми ты общаешься на этом устройстве.', noContacts:'Контактов пока нет', changeAvatar:'Изменить аватар', privacyMask:'Маска приватности', privacyMaskHelp:'Скрывает имена и текст последних сообщений в интерфейсе.', appearance:'Оформление', lightTheme:'Светлая тема', darkTheme:'Тёмная тема', themeHelp:'Переключает светлый и тёмный интерфейс VeilTalk.', calling:'Вызов…', avatarImageOnly:'Выбери изображение PNG, JPEG или WebP.', avatarTooLarge:'Размер аватара должен быть меньше 5 МБ.',
    chats:'Чаты', contacts:'Контакты', settings:'Настройки', newContact:'Новый контакт', createInvite:'Создать приглашение',
    pasteInvite:'Вставить приглашение', copy:'Копировать', copied:'Скопировано', pending:'Ждём подключение', connected:'Подключён', offline:'Офлайн',
    message:'Сообщение', send:'Отправить', call:'Аудиозвонок', video:'Видеозвонок', attach:'Файл', noChats:'Диалогов пока нет',
    profile:'Профиль', displayName:'Имя', language:'Язык', privacy:'Приватность', plan:'Тариф', free:'Бесплатно', pro:'Pro',
    freePlan:'Безлимитный текст · 10 минут звонков/видео в день · файлы до 25 МБ', proPlan:'Безлимитные звонки/видео · HD · демонстрация экрана · P2P-файлы до 1 ГБ',
    upgrade:'VeilTalk Pro — $9.99/месяц', activate:'Активировать лицензию', licenseKey:'Ключ лицензии', billingSoon:'Перед выпуском нужно подключить рабочий checkout.',
    remaining:'Бесплатных минут сегодня', minutes:'мин', incomingCall:'Входящий звонок', answer:'Ответить', decline:'Отклонить', hangup:'Завершить',
    mic:'Микрофон', camera:'Камера', shareScreen:'Показать экран', directP2P:'Прямой WebRTC-медиаканал', relayNote:'Сообщения и сигнализация идут через зашифрованный публичный relay; медиа — напрямую, когда возможно.',
    inviteHelp:'Отправь этот код одному человеку. Внутри случайный секрет комнаты и адрес твоего inbox.', pasteHelp:'Вставь полученный код VeilTalk.',
    save:'Сохранить', delete:'Удалить', version:'Версия', chromeOpen:'VeilTalk доступен, пока работает Chrome. Для звонков лучше закрепить боковую панель.',
    callLimit:'Бесплатный лимит звонков на сегодня исчерпан. Чат продолжает работать.', contactLimit:'Достигнут лимит бесплатных контактов.', invalidInvite:'Некорректное приглашение.',
    notReady:'Контакт ещё не закончил подключение.', fileTooLarge:'Файл больше лимита тарифа.', fileSent:'Файл отправлен', download:'Скачать', search:'Поиск контактов',
    today:'Сегодня', network:'Сеть', online:'Онлайн', reconnecting:'Переподключение', licenseValid:'Pro активен', licenseInvalid:'Лицензия недействительна',
    subscription:'Подписка', directOnly:'Без собственных серверов', about:'О приложении', localData:'История чатов, контакты и профиль хранятся локально в Chrome.',
    needTurn:'В некоторых корпоративных и строгих сетях нужен TURN-relay; в MVP используется только публичный STUN.'
  },
  de: {
    brandTag:'private Chats und Anrufe', heroTitle:'Verbindung ohne Grenzen', heroText:'Private Nachrichten und Browser-Anrufe — schnell, ruhig und ohne Werbung.', newChat:'Neuer Chat', emptyHelp:'Erstelle eine Einladung für einen privaten Chat.', contactsHelp:'Kontakte werden auf diesem Gerät gespeichert.', noContacts:'Noch keine Kontakte', changeAvatar:'Avatar ändern', privacyMask:'Privatsphäre-Maske', privacyMaskHelp:'Blendet Namen und Nachrichtenvorschauen aus.', appearance:'Darstellung', lightTheme:'Helles Design', darkTheme:'Dunkles Design', themeHelp:'Zwischen hellem und dunklem Design wechseln.', calling:'Anrufen…', avatarImageOnly:'Wähle ein PNG-, JPEG- oder WebP-Bild.', avatarTooLarge:'Das Avatarbild muss kleiner als 5 MB sein.',
    chats:'Chats', contacts:'Kontakte', settings:'Einstellungen', newContact:'Neuer Kontakt', createInvite:'Einladung erstellen', pasteInvite:'Einladung einfügen',
    copy:'Kopieren', copied:'Kopiert', pending:'Warte auf Kontakt', connected:'Verbunden', offline:'Offline', message:'Nachricht', send:'Senden', call:'Sprachanruf', video:'Videoanruf', attach:'Datei',
    noChats:'Noch keine Unterhaltungen', profile:'Profil', displayName:'Anzeigename', language:'Sprache', privacy:'Datenschutz', plan:'Tarif', free:'Kostenlos', pro:'Pro',
    freePlan:'Unbegrenzter Textchat · 10 Min. Anrufe/Video pro Tag · 25-MB-Dateien', proPlan:'Unbegrenzte Anrufe/Video · HD · Bildschirmfreigabe · bis 1 GB P2P-Dateien',
    upgrade:'Upgrade auf Pro — 9,99 $/Monat', activate:'Lizenz aktivieren', licenseKey:'Lizenzschlüssel', billingSoon:'Vor der Veröffentlichung ist eine Live-Checkout-Konfiguration erforderlich.',
    remaining:'Kostenlose Anrufzeit heute', minutes:'Min.', incomingCall:'Eingehender Anruf', answer:'Annehmen', decline:'Ablehnen', hangup:'Auflegen', mic:'Mikrofon', camera:'Kamera', shareScreen:'Bildschirm teilen',
    directP2P:'Direkte WebRTC-Medien', relayNote:'Nachrichten/Signalisierung laufen verschlüsselt über einen öffentlichen Relay; Medien möglichst direkt.', inviteHelp:'Sende diesen Einladungscode an eine Person.',
    pasteHelp:'Füge den erhaltenen VeilTalk-Code ein.', save:'Speichern', delete:'Löschen', version:'Version', chromeOpen:'VeilTalk bleibt erreichbar, solange Chrome läuft.', callLimit:'Kostenloses Tageslimit erreicht. Chat funktioniert weiter.',
    contactLimit:'Kostenloses Kontaktlimit erreicht.', invalidInvite:'Ungültige Einladung.', notReady:'Kontakt hat die Kopplung noch nicht abgeschlossen.', fileTooLarge:'Datei überschreitet das Tariflimit.', fileSent:'Datei gesendet', download:'Herunterladen',
    search:'Kontakte suchen', today:'Heute', network:'Netzwerk', online:'Online', reconnecting:'Neu verbinden', licenseValid:'Pro aktiv', licenseInvalid:'Lizenz ungültig', subscription:'Abonnement', directOnly:'Keine eigenen Server',
    about:'Über', localData:'Chatverlauf, Kontakte und Profil werden lokal in Chrome gespeichert.', needTurn:'Einige restriktive Netze benötigen TURN; dieses MVP nutzt nur öffentliches STUN.'
  },
  fr: {
    brandTag:'chats et appels privés', heroTitle:'Connexion sans frontières', heroText:'Messages privés et appels dans le navigateur, rapides et sans publicité.', newChat:'Nouveau chat', emptyHelp:'Créez une invitation pour commencer.', contactsHelp:'Les contacts sont enregistrés sur cet appareil.', noContacts:'Aucun contact', changeAvatar:'Changer l’avatar', privacyMask:'Masque de confidentialité', privacyMaskHelp:'Masque les noms et les aperçus des messages.', appearance:'Apparence', lightTheme:'Thème clair', darkTheme:'Thème sombre', themeHelp:'Basculer entre les thèmes clair et sombre.', calling:'Appel…', avatarImageOnly:'Choisissez une image PNG, JPEG ou WebP.', avatarTooLarge:'L’avatar doit faire moins de 5 Mo.',
    chats:'Chats', contacts:'Contacts', settings:'Réglages', newContact:'Nouveau contact', createInvite:'Créer une invitation', pasteInvite:'Coller une invitation', copy:'Copier', copied:'Copié',
    pending:'En attente', connected:'Connecté', offline:'Hors ligne', message:'Message', send:'Envoyer', call:'Appel audio', video:'Appel vidéo', attach:'Fichier', noChats:'Aucune conversation', profile:'Profil',
    displayName:'Nom affiché', language:'Langue', privacy:'Confidentialité', plan:'Offre', free:'Gratuit', pro:'Pro', freePlan:'Chat texte illimité · 10 min appels/vidéo par jour · fichiers 25 Mo',
    proPlan:'Appels/vidéo illimités · HD · partage écran · fichiers P2P jusqu’à 1 Go', upgrade:'Passer à Pro — 9,99 $/mois', activate:'Activer la licence', licenseKey:'Clé de licence', billingSoon:'Une configuration de paiement active est requise avant la publication.',
    remaining:'Temps gratuit aujourd’hui', minutes:'min', incomingCall:'Appel entrant', answer:'Répondre', decline:'Refuser', hangup:'Raccrocher', mic:'Micro', camera:'Caméra', shareScreen:'Partager l’écran', directP2P:'Média WebRTC direct',
    relayNote:'Messages/signalisation via relais public chiffré; média direct si possible.', inviteHelp:'Envoyez ce code à une personne.', pasteHelp:'Collez le code VeilTalk reçu.', save:'Enregistrer', delete:'Supprimer', version:'Version',
    chromeOpen:'VeilTalk reste joignable tant que Chrome fonctionne.', callLimit:'Limite gratuite atteinte. Le chat continue.', contactLimit:'Limite de contacts gratuits atteinte.', invalidInvite:'Invitation invalide.', notReady:'Le contact n’a pas terminé l’association.',
    fileTooLarge:'Fichier trop volumineux pour votre offre.', fileSent:'Fichier envoyé', download:'Télécharger', search:'Rechercher', today:'Aujourd’hui', network:'Réseau', online:'En ligne', reconnecting:'Reconnexion', licenseValid:'Pro actif', licenseInvalid:'Licence invalide',
    subscription:'Abonnement', directOnly:'Sans serveurs propriétaires', about:'À propos', localData:'Historique, contacts et profil stockés localement dans Chrome.', needTurn:'Certains réseaux restrictifs nécessitent TURN; ce MVP utilise seulement STUN public.'
  },
  es: {
    brandTag:'chats y llamadas privadas', heroTitle:'Conexión sin fronteras', heroText:'Mensajes privados y llamadas en el navegador, rápidos y sin anuncios.', newChat:'Nuevo chat', emptyHelp:'Crea una invitación para empezar.', contactsHelp:'Los contactos se guardan en este dispositivo.', noContacts:'Aún no hay contactos', changeAvatar:'Cambiar avatar', privacyMask:'Máscara de privacidad', privacyMaskHelp:'Oculta nombres y vistas previas de mensajes.', appearance:'Apariencia', lightTheme:'Tema claro', darkTheme:'Tema oscuro', themeHelp:'Cambia entre el tema claro y oscuro.', calling:'Llamando…', avatarImageOnly:'Elige una imagen PNG, JPEG o WebP.', avatarTooLarge:'El avatar debe ocupar menos de 5 MB.',
    chats:'Chats', contacts:'Contactos', settings:'Ajustes', newContact:'Nuevo contacto', createInvite:'Crear invitación', pasteInvite:'Pegar invitación', copy:'Copiar', copied:'Copiado', pending:'Esperando contacto', connected:'Conectado', offline:'Sin conexión',
    message:'Mensaje', send:'Enviar', call:'Llamada de voz', video:'Videollamada', attach:'Archivo', noChats:'Aún no hay conversaciones', profile:'Perfil', displayName:'Nombre', language:'Idioma', privacy:'Privacidad', plan:'Plan', free:'Gratis', pro:'Pro',
    freePlan:'Chat de texto ilimitado · 10 min de llamadas/vídeo al día · archivos de 25 MB', proPlan:'Llamadas/vídeo ilimitados · HD · compartir pantalla · archivos P2P hasta 1 GB', upgrade:'Mejorar a Pro — 9,99 $/mes',
    activate:'Activar licencia', licenseKey:'Clave de licencia', billingSoon:'Se requiere una configuración de pago activa antes de publicar.', remaining:'Tiempo gratis hoy', minutes:'min', incomingCall:'Llamada entrante', answer:'Responder', decline:'Rechazar', hangup:'Colgar',
    mic:'Micrófono', camera:'Cámara', shareScreen:'Compartir pantalla', directP2P:'Medios WebRTC directos', relayNote:'Mensajes/señalización por relay público cifrado; medios directos cuando sea posible.', inviteHelp:'Envía este código a una persona.',
    pasteHelp:'Pega el código VeilTalk recibido.', save:'Guardar', delete:'Eliminar', version:'Versión', chromeOpen:'VeilTalk sigue disponible mientras Chrome esté abierto.', callLimit:'Límite gratuito alcanzado. El chat sigue funcionando.', contactLimit:'Límite de contactos gratuitos alcanzado.',
    invalidInvite:'Invitación inválida.', notReady:'El contacto aún no completó el emparejamiento.', fileTooLarge:'El archivo supera el límite del plan.', fileSent:'Archivo enviado', download:'Descargar', search:'Buscar contactos', today:'Hoy', network:'Red', online:'En línea', reconnecting:'Reconectando',
    licenseValid:'Pro activo', licenseInvalid:'Licencia no válida', subscription:'Suscripción', directOnly:'Sin servidores propios', about:'Acerca de', localData:'Historial, contactos y perfil se guardan localmente en Chrome.', needTurn:'Algunas redes restrictivas requieren TURN; este MVP usa solo STUN público.'
  }
};

const EXTRA = {
  en: {
    chatActions:'Chat actions', emoji:'Emoji', share:'Share', close:'Close', cancel:'Cancel',
    shareInviteText:'Join me on VeilTalk with this private invite:', clearHistory:'Clear history', deleteChat:'Delete chat',
    clearHistoryConfirm:'Delete every message and downloaded file in this chat on this device?',
    deleteChatConfirm:'Delete this contact, its messages and downloaded files from this device?',
    manageSubscription:'Manage subscription', turnReady:'TURN fallback is enabled for restrictive networks.',
    billingSetupRequired:'Payments are not live yet: connect a Monetize paywall and payment processor first.',
    callFailed:'The call could not connect. Check microphone/camera access and try again.',
    fileTransferBusy:'Finish the current file transfer first.', fileFailed:'The file transfer failed. Try again.',
    fileUnavailable:'This file is no longer stored on this device.', file:'File',
    file_connecting:'connecting', file_sending:'sending', file_sent:'sent', file_receiving:'receiving', file_received:'received', file_failed:'failed'
  },
  ru: {
    chatActions:'Действия с чатом', emoji:'Смайлики', share:'Поделиться', close:'Закрыть', cancel:'Отмена',
    shareInviteText:'Присоединяйся ко мне в VeilTalk по приватному приглашению:', clearHistory:'Очистить историю', deleteChat:'Удалить чат',
    clearHistoryConfirm:'Удалить все сообщения и загруженные файлы этого чата с устройства?',
    deleteChatConfirm:'Удалить контакт, сообщения и загруженные файлы с этого устройства?',
    manageSubscription:'Управление подпиской', turnReady:'Для строгих сетей включён резервный TURN-канал.',
    billingSetupRequired:'Оплата ещё не активна: сначала подключи paywall Monetize и платёжного провайдера.',
    callFailed:'Не удалось соединить звонок. Проверь доступ к микрофону и камере и попробуй снова.',
    fileTransferBusy:'Сначала дождись завершения текущей передачи.', fileFailed:'Не удалось передать файл. Попробуй ещё раз.',
    fileUnavailable:'Файл больше не хранится на этом устройстве.', file:'Файл',
    file_connecting:'подключение', file_sending:'отправка', file_sent:'отправлен', file_receiving:'получение', file_received:'получен', file_failed:'ошибка'
  },
  de: {
    chatActions:'Chat-Aktionen', emoji:'Emoji', share:'Teilen', close:'Schließen', cancel:'Abbrechen',
    shareInviteText:'Komm über diese private Einladung zu VeilTalk:', clearHistory:'Verlauf löschen', deleteChat:'Chat löschen',
    clearHistoryConfirm:'Alle Nachrichten und Dateien dieses Chats auf diesem Gerät löschen?', deleteChatConfirm:'Kontakt, Nachrichten und Dateien von diesem Gerät löschen?',
    manageSubscription:'Abonnement verwalten', turnReady:'TURN-Fallback ist für restriktive Netzwerke aktiviert.', billingSetupRequired:'Zahlungen sind noch nicht aktiv. Verbinde zuerst Monetize und einen Zahlungsanbieter.',
    callFailed:'Der Anruf konnte nicht verbunden werden.', fileTransferBusy:'Beende zuerst die laufende Dateiübertragung.', fileFailed:'Dateiübertragung fehlgeschlagen.', fileUnavailable:'Diese Datei ist nicht mehr auf diesem Gerät gespeichert.', file:'Datei',
    file_connecting:'verbinden', file_sending:'senden', file_sent:'gesendet', file_receiving:'empfangen', file_received:'empfangen', file_failed:'fehlgeschlagen'
  },
  fr: {
    chatActions:'Actions du chat', emoji:'Emoji', share:'Partager', close:'Fermer', cancel:'Annuler',
    shareInviteText:'Rejoignez-moi sur VeilTalk avec cette invitation privée :', clearHistory:'Effacer l’historique', deleteChat:'Supprimer le chat',
    clearHistoryConfirm:'Supprimer tous les messages et fichiers de ce chat sur cet appareil ?', deleteChatConfirm:'Supprimer le contact, ses messages et fichiers de cet appareil ?',
    manageSubscription:'Gérer l’abonnement', turnReady:'Le relais TURN est activé pour les réseaux restrictifs.', billingSetupRequired:'Les paiements ne sont pas encore actifs. Connectez Monetize et un prestataire de paiement.',
    callFailed:'Impossible de connecter l’appel.', fileTransferBusy:'Terminez d’abord le transfert en cours.', fileFailed:'Échec du transfert du fichier.', fileUnavailable:'Ce fichier n’est plus stocké sur cet appareil.', file:'Fichier',
    file_connecting:'connexion', file_sending:'envoi', file_sent:'envoyé', file_receiving:'réception', file_received:'reçu', file_failed:'échec'
  },
  es: {
    chatActions:'Acciones del chat', emoji:'Emoji', share:'Compartir', close:'Cerrar', cancel:'Cancelar',
    shareInviteText:'Únete a VeilTalk con esta invitación privada:', clearHistory:'Borrar historial', deleteChat:'Eliminar chat',
    clearHistoryConfirm:'¿Borrar todos los mensajes y archivos de este chat en este dispositivo?', deleteChatConfirm:'¿Eliminar el contacto, sus mensajes y archivos de este dispositivo?',
    manageSubscription:'Gestionar suscripción', turnReady:'El respaldo TURN está activo para redes restrictivas.', billingSetupRequired:'Los pagos aún no están activos. Conecta Monetize y un proveedor de pagos.',
    callFailed:'No se pudo conectar la llamada.', fileTransferBusy:'Termina primero la transferencia actual.', fileFailed:'Error al transferir el archivo.', fileUnavailable:'Este archivo ya no está guardado en este dispositivo.', file:'Archivo',
    file_connecting:'conectando', file_sending:'enviando', file_sent:'enviado', file_receiving:'recibiendo', file_received:'recibido', file_failed:'falló'
  }
};

export function tr(lang, key) {
  return T[lang]?.[key] ?? EXTRA[lang]?.[key] ?? T.en[key] ?? EXTRA.en[key] ?? key;
}
