import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

void main() {
  runApp(const ChernogramApp());
}

class ChernogramApp extends StatelessWidget {
  const ChernogramApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Чернограм',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        primaryColor: const Color(0xFF1E1E1E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1E1E1E),
          secondary: Color(0xFF2D2D2D),
        ),
      ),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ====================== ЭКРАН ЗАСТАВКИ ======================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Логотип звезда-самолет (упрощенная версия)
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2D2D2D),
                border: Border.all(color: Colors.white24, width: 2),
              ),
              child: const Icon(
                Icons.flight_takeoff,
                size: 60,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'ЧЕРНОГРАМ',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Место без слежки и политики',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white54,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(
              color: Colors.white54,
            ),
          ],
        ),
      ),
    );
  }
}

// ====================== ГЛАВНЫЙ ЭКРАН ======================
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  List<Post> posts = [];
  final DatabaseHelper db = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    final loadedPosts = await db.getPosts();
    setState(() {
      posts = loadedPosts;
      if (posts.isEmpty) {
        // Демо-данные (хардкод)
        posts = [
          Post(
            id: 1,
            author: 'Аноним',
            text: 'Добро пожаловать в Чернограм! Здесь все данные хранятся только на твоем устройстве. 🤫',
            timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
          Post(
            id: 2,
            author: 'Путник',
            text: 'Наконец-то место без цензуры и слежки. Свобода слова - это важно!',
            timestamp: DateTime.now().subtract(const Duration(hours: 1)),
          ),
          Post(
            id: 3,
            author: 'Тень',
            text: 'Проверка связи. Никто не следит? 👀',
            timestamp: DateTime.now().subtract(const Duration(hours: 3)),
          ),
        ];
        await db.insertPosts(posts);
      }
    });
  }

  Future<void> _addPost(String text) async {
    if (text.isEmpty) return;
    final newPost = Post(
      id: DateTime.now().millisecondsSinceEpoch,
      author: 'Аноним',
      text: text,
      timestamp: DateTime.now(),
    );
    await db.insertPost(newPost);
    setState(() {
      posts.insert(0, newPost);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white38,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Лента'),
          BottomNavigationBarItem(icon: Icon(Icons.add_circle), label: 'Создать'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Профиль'),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          FeedScreen(posts: posts, onAddPost: _addPost),
          CreatePostScreen(onAddPost: _addPost),
          ProfileScreen(),
        ],
      ),
    );
  }
}

// ====================== ЭКРАН ЛЕНТЫ ======================
class FeedScreen extends StatelessWidget {
  final List<Post> posts;
  final Function(String) onAddPost;

  const FeedScreen({super.key, required this.posts, required this.onAddPost});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Шапка
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white12)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Лента',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '🔒 100% локально',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
        // Список постов
        Expanded(
          child: posts.isEmpty
              ? const Center(child: Text('Нет постов. Создай первый!'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final post = posts[index];
                    return Card(
                      color: const Color(0xFF2D2D2D),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.white24,
                                  child: Text(
                                    post.author[0].toUpperCase(),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  post.author,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _timeAgo(post.timestamp),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white38,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(post.text),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин. назад';
    if (diff.inHours < 24) return '${diff.inHours} ч. назад';
    return '${diff.inDays} д. назад';
  }
}

// ====================== ЭКРАН СОЗДАНИЯ ПОСТА ======================
class CreatePostScreen extends StatefulWidget {
  final Function(String) onAddPost;

  const CreatePostScreen({super.key, required this.onAddPost});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 40),
          const Text(
            'Создать пост',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          const Text(
            'Все данные сохраняются ТОЛЬКО на твоем устройстве',
            style: TextStyle(color: Colors.white54, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          TextField(
            controller: _controller,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Что у тебя на уме?',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF2D2D2D),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            maxLines: 6,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (_controller.text.isNotEmpty) {
                  widget.onAddPost(_controller.text);
                  _controller.clear();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Пост опубликован локально!')),
                  );
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('ОПУБЛИКОВАТЬ', fontWeight: FontWeight.bold),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '🔒 Никаких серверов. Только твое устройство',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ====================== ЭКРАН ПРОФИЛЯ ======================
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String name = 'Аноним';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      name = prefs.getString('username') ?? 'Аноним';
    });
  }

  Future<void> _changeName() async {
    final TextEditingController controller = TextEditingController(text: name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Изменить имя'),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Введите имя'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('username', controller.text);
              setState(() => name = controller.text);
              Navigator.pop(context);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 60,
              backgroundColor: Colors.white24,
              child: Text(
                name[0].toUpperCase(),
                style: const TextStyle(fontSize: 48, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Постов: 0',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: const [
                  Icon(Icons.security, color: Colors.white54, size: 40),
                  SizedBox(height: 10),
                  Text(
                    'Все данные хранятся локально',
                    style: TextStyle(color: Colors.white54),
                  ),
                  Text(
                    'Никаких серверов и слежки',
                    style: TextStyle(fontSize: 12, color: Colors.white38),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _changeName,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Изменить имя'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ====================== МОДЕЛЬ ПОСТА ======================
class Post {
  final int id;
  final String author;
  final String text;
  final DateTime timestamp;

  Post({
    required this.id,
    required this.author,
    required this.text,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'author': author,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  factory Post.fromMap(Map<String, dynamic> map) => Post(
        id: map['id'],
        author: map['author'],
        text: map['text'],
        timestamp: DateTime.parse(map['timestamp']),
      );
}

// ====================== БАЗА ДАННЫХ (ЛОКАЛЬНАЯ) ======================
class DatabaseHelper {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/chernogram.db';
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE posts(
        id INTEGER PRIMARY KEY,
        author TEXT,
        text TEXT,
        timestamp TEXT
      )
    ''');
  }

  Future<List<Post>> getPosts() async {
    final db = await database;
    final result = await db.query('posts', orderBy: 'timestamp DESC');
    return result.map((map) => Post.fromMap(map)).toList();
  }

  Future<void> insertPost(Post post) async {
    final db = await database;
    await db.insert('posts', post.toMap());
  }

  Future<void> insertPosts(List<Post> posts) async {
    final db = await database;
    for (var post in posts) {
      await db.insert('posts', post.toMap());
    }
  }
}