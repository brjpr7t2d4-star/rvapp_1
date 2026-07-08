import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

const bool kSeedSampleLocations = false;

void main() {
  runApp(const RVOwnerApp());
}

// Data Models
class RVLocation {
  final String id;
  final String name;
  final String type;
  final double latitude;
  final double longitude;
  final String? address;
  final String? details;
  final String addedBy;
  final DateTime createdDate;
  final List<Review> reviews;
  final List<String> photos;
  final List<String> videos;

  RVLocation({
    required this.id,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.address,
    this.details,
    required this.addedBy,
    DateTime? createdDate,
    List<Review>? reviews,
    List<String>? photos,
    List<String>? videos,
  })  : createdDate = createdDate ?? DateTime.now(),
        reviews = reviews ?? [],
        photos = photos ?? [],
        videos = videos ?? [];

  double getAverageRating() {
    if (reviews.isEmpty) return 0;
    double sum = reviews.fold(0, (total, review) => total + review.rating);
    return sum / reviews.length;
  }

  void addReview(Review review) {
    reviews.add(review);
  }
}

class PendingLocationSubmission {
  final String id;
  final String name;
  final String type;
  final double latitude;
  final double longitude;
  final String? address;
  final String? details;
  final String submittedBy;
  final DateTime submittedAt;
  final List<String> photos;
  final List<String> videos;

  PendingLocationSubmission({
    required this.id,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.address,
    this.details,
    required this.submittedBy,
    DateTime? submittedAt,
    List<String>? photos,
    List<String>? videos,
  })  : submittedAt = submittedAt ?? DateTime.now(),
        photos = photos ?? [],
        videos = videos ?? [];
}

class Review {
  final String username;
  final String comment;
  final double rating;
  final String? photo;
  final DateTime createdDate;

  Review({
    required this.username,
    required this.comment,
    required this.rating,
    this.photo,
    DateTime? createdDate,
  }) : createdDate = createdDate ?? DateTime.now();
}

class RVUser {
  final String username;
  final List<Review> reviews;
  int locationsAdded;
  String? rvMake;
  String? rvModel;
  String? rvYear;
  final List<String> following; // Users this user follows
  final List<String> followers; // Users following this user
  final List<Adventure> adventures;
  final List<String> photos; // Photo URLs/paths
  final List<String> followRequests; // Usernames requesting to follow
  UserPreferences preferences;
  String? profilePicture; // Profile picture URL
  String? bio; // User bio
  Map<String, String> socials; // Social media links (platform -> handle/url)

  RVUser({required this.username})
      : reviews = [],
        locationsAdded = 0,
        rvMake = null,
        rvModel = null,
        rvYear = null,
        following = [],
        followers = [],
        adventures = [],
        photos = [],
        followRequests = [],
        preferences = UserPreferences(),
        profilePicture = null,
        bio = null,
        socials = {};

  void addReview(Review review) {
    reviews.add(review);
  }

  void incrementLocationsAdded() {
    locationsAdded++;
  }

  void updateRVInfo(String make, String model, String year) {
    rvMake = make;
    rvModel = model;
    rvYear = year;
  }

  void followUser(String userToFollow) {
    if (!following.contains(userToFollow)) {
      following.add(userToFollow);
    }
  }

  void unfollowUser(String userToUnfollow) {
    following.remove(userToUnfollow);
  }

  void addFollower(String follower) {
    if (!followers.contains(follower)) {
      followers.add(follower);
    }
  }

  void removeFollower(String follower) {
    followers.remove(follower);
  }

  void addFollowRequest(String requester) {
    if (requester == username) {
      return;
    }
    if (!followRequests.contains(requester) && !followers.contains(requester)) {
      followRequests.add(requester);
    }
  }

  void removeFollowRequest(String requester) {
    followRequests.remove(requester);
  }

  void addAdventure(Adventure adventure) {
    adventures.add(adventure);
  }

  void addPhoto(String photoPath) {
    photos.add(photoPath);
  }

  void updateBio(String newBio) {
    bio = newBio;
  }

  void updateProfilePicture(String picturePath) {
    profilePicture = picturePath;
  }

  void addSocial(String platform, String handle) {
    socials[platform] = handle;
  }

  void removeSocial(String platform) {
    socials.remove(platform);
  }
}

class Adventure {
  final String id;
  final String title;
  final String description;
  final String locationName;
  final DateTime date;
  final List<String> photos;
  final List<String> videos;
  final double rating;
  final bool isLocationSubmission;
  final String? locationType;
  final double? latitude;
  final double? longitude;

  Adventure({
    required this.id,
    required this.title,
    required this.description,
    required this.locationName,
    required this.date,
    List<String>? photos,
    List<String>? videos,
    this.rating = 5,
    this.isLocationSubmission = false,
    this.locationType,
    this.latitude,
    this.longitude,
  })  : photos = photos ?? [],
        videos = videos ?? [];
}

class _SocialFeedEntry {
  final String username;
  final Adventure post;

  const _SocialFeedEntry({
    required this.username,
    required this.post,
  });
}

List<String> _parseMediaUrls(String rawValue) {
  return rawValue
      .split(RegExp(r'[\n,]'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
}

Widget _buildMediaAttachments(
  BuildContext context, {
  required List<String> photos,
  required List<String> videos,
}) {
  if (photos.isEmpty && videos.isEmpty) {
    return const SizedBox.shrink();
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (photos.isNotEmpty) ...[
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  photos[index],
                  width: 110,
                  height: 110,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) {
                    return Container(
                      width: 110,
                      height: 110,
                      color: Colors.grey[200],
                      alignment: Alignment.center,
                      child: Icon(Icons.broken_image, color: Colors.grey[500]),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
      if (videos.isNotEmpty) ...[
        const SizedBox(height: 12),
        ...videos.map(
          (videoUrl) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F9F7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1B5E4B).withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.play_circle_fill, color: Color(0xFF1B5E4B)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    videoUrl,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}

class UserPreferences {
  bool showWeatherAlerts;
  bool showRoadConditions;
  bool shareLocation;
  bool allowMessages;
  bool requireFollowApproval;
  String? preferredMap; // 'standard', 'satellite', 'terrain'
  List<String> favoriteLocationTypes;
  String coordinateFormat; // 'decimal', 'mgrs'
  String distanceUnit; // 'km', 'miles'

  UserPreferences({
    this.showWeatherAlerts = true,
    this.showRoadConditions = true,
    this.shareLocation = false,
    this.allowMessages = true,
    this.requireFollowApproval = false,
    this.preferredMap = 'standard',
    List<String>? favoriteLocationTypes,
    this.coordinateFormat = 'decimal',
    this.distanceUnit = 'km',
  }) : favoriteLocationTypes = favoriteLocationTypes ?? ['Camping', 'Parking'];
}

// MGRS Converter Utility
String convertToMGRS(double latitude, double longitude) {
  // Simplified MGRS converter (basic implementation)
  // Real MGRS uses complex calculations, this is a simplified version
  
  // Determine the latitude band letter (C-X, excluding I and O)
  const latitudeBands = 'CDEFGHJKLMNPQRSTUVWX';
  int latBandIndex = ((latitude + 80) / 8).floor().clamp(0, 19);
  String latBand = latitudeBands[latBandIndex];
  
  // Determine zone number (1-60)
  int zoneNumber = ((longitude + 180) / 6).floor() + 1;
  
  // For simplification, use false easting/northing based on coordinates
  int falseEasting = ((longitude % 6 + 180) * 100000).toInt() % 1000000;
  int falseNorthing = ((latitude % 8 + 80) * 100000).toInt() % 1000000;
  
  String easting = falseEasting.toString().padLeft(5, '0');
  String northing = falseNorthing.toString().padLeft(5, '0');
  
  return '$zoneNumber$latBand $easting $northing';
}

// Distance Calculator - using Haversine formula
double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0;
  
  final dLat = _degreesToRadians(lat2 - lat1);
  final dLon = _degreesToRadians(lon2 - lon1);
  
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
      sin(dLon / 2) * sin(dLon / 2);
  
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadiusKm * c;
}

double _degreesToRadians(double degrees) {
  return degrees * pi / 180;
}

// Location Manager - needs to be defined before pages that use it
class RVLocationManager {
  final List<RVLocation> locations = [];
  final List<PendingLocationSubmission> pendingLocationSubmissions = [];
  final Map<String, RVUser> users = {};
  int _idCounter = 0;
  int _pendingIdCounter = 0;

  void createUser(String username) {
    if (!users.containsKey(username)) {
      users[username] = RVUser(username: username);
    }
  }

  void addRVLocation(
    String name,
    String type,
    double latitude,
    double longitude,
    String addedBy, {
    String? address,
    String? details,
    List<String>? photos,
    List<String>? videos,
  }) {
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      throw Exception('Invalid coordinates');
    }

    final location = RVLocation(
      id: _idCounter.toString(),
      name: name,
      type: type,
      latitude: latitude,
      longitude: longitude,
      address: address,
      details: details,
      addedBy: addedBy,
      photos: photos,
      videos: videos,
    );

    locations.add(location);
    if (users.containsKey(addedBy)) {
      users[addedBy]!.incrementLocationsAdded();
    }
    _idCounter++;
  }

  void addReviewToLocation(int locationIndex, String username, String comment, double rating) {
    if (locationIndex >= 0 && locationIndex < locations.length) {
      if (rating < 1 || rating > 5) {
        throw Exception('Rating must be between 1 and 5');
      }

      final review = Review(
        username: username,
        comment: comment,
        rating: rating,
      );

      locations[locationIndex].addReview(review);

      if (users.containsKey(username)) {
        users[username]!.addReview(review);
      }
    }
  }

  void submitLocationForApproval(
    String name,
    String type,
    double latitude,
    double longitude,
    String submittedBy, {
    String? address,
    String? details,
    List<String>? photos,
    List<String>? videos,
  }) {
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      throw Exception('Invalid coordinates');
    }

    final duplicateApproved = locations.any((location) {
      final sameType = location.type == type;
      final closeEnough = calculateDistance(
            location.latitude,
            location.longitude,
            latitude,
            longitude,
          ) <
          0.15;
      return sameType && closeEnough;
    });

    if (duplicateApproved) {
      throw Exception('A similar approved location already exists nearby.');
    }

    final duplicatePending = pendingLocationSubmissions.any((submission) {
      final sameType = submission.type == type;
      final sameUser = submission.submittedBy == submittedBy;
      final closeEnough = calculateDistance(
            submission.latitude,
            submission.longitude,
            latitude,
            longitude,
          ) <
          0.15;
      return sameType && sameUser && closeEnough;
    });

    if (duplicatePending) {
      throw Exception('You already have a similar pending submission nearby.');
    }

    pendingLocationSubmissions.add(
      PendingLocationSubmission(
        id: 'pending_${_pendingIdCounter++}',
        name: name,
        type: type,
        latitude: latitude,
        longitude: longitude,
        address: address,
        details: details,
        submittedBy: submittedBy,
        photos: photos,
        videos: videos,
      ),
    );
  }

  void approvePendingLocation(String pendingId) {
    final index = pendingLocationSubmissions.indexWhere((submission) => submission.id == pendingId);
    if (index < 0) {
      throw Exception('Pending submission not found.');
    }

    final submission = pendingLocationSubmissions.removeAt(index);
    addRVLocation(
      submission.name,
      submission.type,
      submission.latitude,
      submission.longitude,
      submission.submittedBy,
      address: submission.address,
      details: submission.details,
      photos: submission.photos,
      videos: submission.videos,
    );
  }

  void rejectPendingLocation(String pendingId) {
    pendingLocationSubmissions.removeWhere((submission) => submission.id == pendingId);
  }
}

// Main App
class RVOwnerApp extends StatelessWidget {
  const RVOwnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF0F4C81);
    const secondary = Color(0xFFFF8A5B);
    const surface = Color(0xFFFFFFFF);
    const onSurface = Color(0xFF111827);
    const surfaceVariant = Color(0xFFF3F5F8);

    return MaterialApp(
      title: 'Nomad Network',
      theme: ThemeData(
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: primary,
          onPrimary: Colors.white,
          secondary: secondary,
          onSecondary: Color(0xFF2E1B00),
          error: Color(0xFFB42318),
          onError: Colors.white,
          surface: surface,
          onSurface: onSurface,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: surfaceVariant,
        appBarTheme: AppBarTheme(
          backgroundColor: surface,
          foregroundColor: onSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          titleTextStyle: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: onSurface,
            letterSpacing: 0.2,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: surface,
          indicatorColor: const Color(0x1A0F4C81),
          elevation: 0,
          height: 68,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? primary : const Color(0xFF7A8A89),
              letterSpacing: 0.2,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: primary, size: 28);
            }
            return const IconThemeData(color: Color(0xFF95A99C), size: 24);
          }),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
        ),
        textTheme: const TextTheme().copyWith(
          headlineLarge: const TextStyle(
            color: onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 28,
            letterSpacing: -0.6,
          ),
          headlineSmall: const TextStyle(
            color: onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: -0.2,
          ),
          titleMedium: const TextStyle(
            color: onSurface,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
          bodyMedium: const TextStyle(
            color: const Color(0xFF3B4A49),
            fontSize: 14,
          ),
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        dividerColor: const Color(0xFFE5EAF0),
      ),
      home: const AppEntryPage(),
    );
  }
}

class AppEntryPage extends StatefulWidget {
  const AppEntryPage({super.key});

  @override
  State<AppEntryPage> createState() => _AppEntryPageState();
}

class _AppEntryPageState extends State<AppEntryPage> {
  bool _isLoading = true;
  bool _needsOnboarding = true;
  String _username = 'CurrentUser';

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_done') ?? false;
    final storedUsername = prefs.getString('username');

    if (!mounted) {
      return;
    }

    setState(() {
      _needsOnboarding = !onboardingDone;
      _username = storedUsername?.trim().isNotEmpty == true
          ? storedUsername!.trim()
          : 'CurrentUser';
      _isLoading = false;
    });
  }

  Future<void> _completeOnboarding(String username) async {
    final trimmed = username.trim();
    final selectedUsername = trimmed.isEmpty ? 'CurrentUser' : trimmed;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    await prefs.setString('username', selectedUsername);

    if (!mounted) {
      return;
    }

    setState(() {
      _username = selectedUsername;
      _needsOnboarding = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_needsOnboarding) {
      return WelcomePage(
        onContinueAsGuest: () => _completeOnboarding('CurrentUser'),
        onSignup: _completeOnboarding,
      );
    }

    return HomePage(initialUsername: _username);
  }
}

class WelcomePage extends StatelessWidget {
  final VoidCallback onContinueAsGuest;
  final ValueChanged<String> onSignup;

  const WelcomePage({
    required this.onContinueAsGuest,
    required this.onSignup,
    super.key,
  });

  Future<void> _openSignup(BuildContext context) async {
    final username = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const SignupPage()),
    );

    if (username != null && username.trim().isNotEmpty) {
      onSignup(username);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEAF6F4), Color(0xFFFFF8EE), Color(0xFFF4F8FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Text(
                  'Nomad Network',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1D2B2A),
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Find nearby campgrounds and rest areas, share spots, and travel smarter.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF546463),
                    height: 1.35,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _openSignup(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Create Account'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onContinueAsGuest,
                  child: const Text('Continue as Guest'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final TextEditingController _usernameController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  void _submit() {
    final username = _usernameController.text.trim();
    if (username.length < 3) {
      setState(() {
        _errorText = 'Username must be at least 3 characters';
      });
      return;
    }

    Navigator.of(context).pop(username);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pick a username to get started.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _usernameController,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Username',
                hintText: 'e.g. RoadNomad',
                errorText: _errorText,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submit,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

// Home Page with Tab Navigation
class HomePage extends StatefulWidget {
  final String initialUsername;

  const HomePage({super.key, required this.initialUsername});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late RVLocationManager locationManager;
  int _selectedIndex = 2;
  late final String _currentUsername;

  @override
  void initState() {
    super.initState();
    _currentUsername = widget.initialUsername;
    locationManager = RVLocationManager();
    locationManager.createUser(_currentUsername);
    _initializeSampleData();
  }

  void _initializeSampleData() {
    // Create sample users
    locationManager.createUser('Admin');
    locationManager.createUser('Alice123');
    locationManager.createUser('Bob456');

    // Add RV info and profile info to users
    final admin = locationManager.users['Admin'];
    admin?.updateBio('Full-time RVer exploring the USA 🚐');
    admin?.addSocial('Instagram', '@adminrv');
    admin?.addPhoto('https://images.unsplash.com/photo-1464207687429-7505649dae38?w=300');
    admin?.addPhoto('https://images.unsplash.com/photo-1469854523086-cc02fe5d8800?w=300');

    final alice = locationManager.users['Alice123'];
    alice?.updateRVInfo('Winnebago', 'Minnie Winnie', '2022');
    alice?.updateBio('Love camping and mountain views 🏕️ with my Winnie!');
    alice?.addSocial('Instagram', '@alice.adventures');
    alice?.addSocial('Twitter', '@alice_rv');
    alice?.addPhoto('https://images.unsplash.com/photo-1516886657613-9f3515b0c78f?w=300');
    alice?.addPhoto('https://images.unsplash.com/photo-1437522292490-8e18b1f6f5f6?w=300');
    alice?.addPhoto('https://images.unsplash.com/photo-1469854523086-cc02fe5d8800?w=300');
    alice?.addAdventure(Adventure(
      id: '1',
      title: 'Yosemite Adventure',
      description: 'Amazing views and great camping spots! The wildlife viewing was incredible.',
      locationName: 'Yosemite National Park',
      date: DateTime.now().subtract(const Duration(days: 5)),
      photos: [
        'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=600',
        'https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=600',
      ],
      rating: 5,
    ));

    final bob = locationManager.users['Bob456'];
    bob?.updateRVInfo('Forest River', 'Salem', '2020');
    bob?.updateBio('Road trip enthusiast 🛣️ | Sharing my travels one mile at a time');
    bob?.addSocial('Instagram', '@bob.travels');
    bob?.addSocial('Facebook', 'Bob RV Adventures');
    bob?.addPhoto('https://images.unsplash.com/photo-1511884642898-4c92249e20b6?w=300');
    bob?.addPhoto('https://images.unsplash.com/photo-1469854523086-cc02fe5d8800?w=300');
    bob?.addAdventure(Adventure(
      id: '2',
      title: 'Rocky Mountains Escape',
      description: 'Breathtaking mountain views and peaceful surroundings.',
      locationName: 'Rocky Mountains',
      date: DateTime.now().subtract(const Duration(days: 3)),
      photos: ['https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=600'],
      rating: 4,
    ));

    // Set up follows
    alice?.followUser('Bob456');
    bob?.addFollower('Alice123');
    bob?.followUser('Admin');
    admin?.addFollower('Bob456');
    alice?.addFollower('Admin');

    if (kSeedSampleLocations) {
      // Add sample locations
      locationManager.addRVLocation(
        'Times Square RV Park',
        'Parking',
        40.7128,
        -74.0060,
        'Admin',
        address: '1500 Broadway, New York, NY 10036',
      );
      locationManager.addRVLocation(
        'Yosemite Viewpoint',
        'Sightseeing',
        37.8651,
        -119.5383,
        'Alice123',
        address: 'CA-120, Groveland, CA 95321',
      );
      locationManager.addRVLocation(
        'Rocky Mountains Campground',
        'Camping',
        39.7392,
        -104.9903,
        'Bob456',
        address: 'Denver, CO 80202',
      );
      locationManager.addRVLocation(
        'Lake Tahoe RV Resort',
        'Camping',
        39.0968,
        -120.0324,
        'Alice123',
        address: 'CA-89, South Lake Tahoe, CA 96150',
      );

      // Add sample reviews
      locationManager.addReviewToLocation(
        0,
        'Alice123',
        'Great place to park! Clean facilities and helpful staff.',
        5,
      );
      locationManager.addReviewToLocation(
        0,
        'Bob456',
        'Really enjoyed the amenities. Would recommend!',
        4,
      );
      locationManager.addReviewToLocation(
        1,
        'Bob456',
        'Beautiful views! Worth the drive.',
        5,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: const Text('Nomad Network'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: _getSelectedPage(),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Theme.of(context).dividerColor),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F4C81).withValues(alpha: 0.07),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.location_on),
                  label: 'Locations',
                ),
                NavigationDestination(
                  icon: Icon(Icons.map),
                  label: 'Map',
                ),
                NavigationDestination(
                  icon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.people),
                  label: 'Social',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _getSelectedPage() {
    switch (_selectedIndex) {
      case 0:
        return LocationsExplorePage(locationManager: locationManager, username: _currentUsername, onUpdate: () => setState(() {}));
      case 1:
        return MapWeatherPage(locationManager: locationManager, username: _currentUsername);
      case 2:
        return DashboardPage(locationManager: locationManager, username: _currentUsername, onUpdate: () => setState(() {}));
      case 3:
        return SocialPage(locationManager: locationManager, username: _currentUsername, onUpdate: () => setState(() {}));
      case 4:
        return SettingsPage(locationManager: locationManager, username: _currentUsername, onUpdate: () => setState(() {}));
      default:
        return Container();
    }
  }
}

// Locations Explore Page - Consolidated view with View, Add, and Search modes
class LocationsExplorePage extends StatefulWidget {
  final RVLocationManager locationManager;
  final String username;
  final VoidCallback onUpdate;

  const LocationsExplorePage({required this.locationManager, required this.username, required this.onUpdate, super.key});

  @override
  State<LocationsExplorePage> createState() => _LocationsExplorePageState();
}

class _LocationsExplorePageState extends State<LocationsExplorePage> {
  int _modeIndex = 0; // 0 = View, 1 = Add, 2 = Search

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Mode selector tabs
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: SegmentedButton<int>(
                  selected: {_modeIndex},
                  onSelectionChanged: (Set<int> newSelection) {
                    setState(() {
                      _modeIndex = newSelection.first;
                    });
                  },
                  segments: const <ButtonSegment<int>>[
                    ButtonSegment<int>(
                      value: 0,
                      label: Text('Browse'),
                      icon: Icon(Icons.list),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      label: Text('Add'),
                      icon: Icon(Icons.add),
                    ),
                    ButtonSegment<int>(
                      value: 2,
                      label: Text('Search'),
                      icon: Icon(Icons.search),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Content area based on selected mode
        Expanded(
          child: _buildModeContent(),
        ),
      ],
    );
  }

  Widget _buildModeContent() {
    switch (_modeIndex) {
      case 0:
        // View mode
        return LocationsListPage(locationManager: widget.locationManager, username: widget.username, onUpdate: widget.onUpdate);
      case 1:
        // Add mode
        return AddLocationPage(
          locationManager: widget.locationManager,
          username: widget.username,
          onUpdate: widget.onUpdate,
        );
      case 2:
        // Search mode
        return SearchPage(locationManager: widget.locationManager, onUpdate: widget.onUpdate);
      default:
        return Container();
    }
  }
}

// Locations List Page
class LocationsListPage extends StatefulWidget {
  final RVLocationManager locationManager;
  final String username;
  final VoidCallback onUpdate;

  const LocationsListPage({required this.locationManager, required this.username, required this.onUpdate, super.key});

  @override
  State<LocationsListPage> createState() => _LocationsListPageState();
}

class _LocationsListPageState extends State<LocationsListPage> {
  static const double _nearbyRadiusMeters = 30000;
  static const double _nearbyRefreshDistanceKm = 0.5;
  String? _filterType;
  Position? _userLocation;
  Position? _lastNearbyFetchPosition;
  bool _loadingLocation = false;
  bool _loadingNearby = false;
  bool _nearbyLoaded = false;
  String? _locationError;
  String? _nearbyError;
  bool _useMockLocation = false;
  Timer? _nearbyRefreshTimer;

  // Mock location: San Francisco area
  static const double mockLatitude = 37.7749;
  static const double mockLongitude = -122.4194;

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
    // Only use mock fallback in web demos; physical phone tests should use real GPS.
    if (kIsWeb) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _userLocation == null && _loadingLocation) {
          _setMockLocation();
        }
      });
    }

    _nearbyRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || _userLocation == null) {
        return;
      }
      unawaited(_refreshNearbyIfMoved());
    });
  }

  @override
  void dispose() {
    _nearbyRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _requestLocationPermission() async {
    try {
      setState(() => _loadingLocation = true);
      
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _locationError = kIsWeb
                ? 'Location services disabled - using test location'
                : 'Location services disabled on this device';
            _loadingLocation = false;
          });
          if (kIsWeb) {
            _setMockLocation();
          }
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _locationError = kIsWeb
                  ? 'Location permission denied - using test location'
                  : 'Location permission denied';
              _loadingLocation = false;
            });
            if (kIsWeb) {
              _setMockLocation();
            }
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _locationError = 'Location permission permanently denied in Settings';
            _loadingLocation = false;
          });
        }
        return;
      }

      if (mounted) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            throw TimeoutException('Could not get current location in time');
          },
        );
        if (mounted && !_useMockLocation) {
          setState(() {
            _userLocation = position;
            _loadingLocation = false;
            _locationError = null;
          });
          await _addCurrentLocationIfMissing(position);
          await _loadNearbyPlaces(position);
        }
      }
    } catch (e) {
      if (mounted) {
        if (kIsWeb) {
          setState(() {
            _locationError = 'Using test location for demo';
            _loadingLocation = false;
          });
          _setMockLocation();
        } else {
          setState(() {
            _locationError = 'Could not get live location: $e';
            _loadingLocation = false;
          });
        }
      }
    }
  }

  Future<void> _addCurrentLocationIfMissing(Position position) async {
    final alreadyAdded = widget.locationManager.locations.any(
      (location) {
        if (location.addedBy != widget.username) {
          return false;
        }
        return calculateDistance(
              location.latitude,
              location.longitude,
              position.latitude,
              position.longitude,
            ) <
            0.1;
      },
    );

    final alreadyPending = widget.locationManager.pendingLocationSubmissions.any(
      (submission) {
        if (submission.submittedBy != widget.username) {
          return false;
        }
        return calculateDistance(
              submission.latitude,
              submission.longitude,
              position.latitude,
              position.longitude,
            ) <
            0.1;
      },
    );

    if (alreadyAdded || alreadyPending) {
      return;
    }

    String locationName = 'My Current Location';
    String? address = 'Detected from your device GPS';

    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final titleParts = [
          place.locality,
          place.administrativeArea,
          place.country,
        ]
            .whereType<String>()
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList();

        if (titleParts.isNotEmpty) {
          locationName = titleParts.take(2).join(', ');
        }

        final addressParts = [
          place.name,
          place.subLocality,
          place.locality,
          place.administrativeArea,
          place.postalCode,
          place.country,
        ]
            .whereType<String>()
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList();

        if (addressParts.isNotEmpty) {
          address = addressParts.join(', ');
        }
      }
    } catch (_) {
      // Keep GPS fallback text if reverse geocoding is unavailable.
    }

    if (widget.username.toLowerCase() == 'admin') {
      widget.locationManager.addRVLocation(
        locationName,
        'Parking',
        position.latitude,
        position.longitude,
        widget.username,
        address: address,
      );
    } else {
      widget.locationManager.submitLocationForApproval(
        locationName,
        'Parking',
        position.latitude,
        position.longitude,
        widget.username,
        address: address,
      );
    }
    widget.onUpdate();
  }

  Future<void> _loadNearbyPlaces(Position position, {bool forceRefresh = false}) async {
    if ((!forceRefresh && _nearbyLoaded) || _loadingNearby) {
      return;
    }

    setState(() {
      _loadingNearby = true;
      _nearbyError = null;
    });

    try {
      final query = '''
[out:json][timeout:25];
(
  node["tourism"="camp_site"](around:${_nearbyRadiusMeters.toInt()},${position.latitude},${position.longitude});
  way["tourism"="camp_site"](around:${_nearbyRadiusMeters.toInt()},${position.latitude},${position.longitude});
  node["tourism"="caravan_site"](around:${_nearbyRadiusMeters.toInt()},${position.latitude},${position.longitude});
  way["tourism"="caravan_site"](around:${_nearbyRadiusMeters.toInt()},${position.latitude},${position.longitude});
  node["highway"="rest_area"](around:${_nearbyRadiusMeters.toInt()},${position.latitude},${position.longitude});
  way["highway"="rest_area"](around:${_nearbyRadiusMeters.toInt()},${position.latitude},${position.longitude});
  node["highway"="services"](around:${_nearbyRadiusMeters.toInt()},${position.latitude},${position.longitude});
  way["highway"="services"](around:${_nearbyRadiusMeters.toInt()},${position.latitude},${position.longitude});
  node["amenity"="fuel"](around:${_nearbyRadiusMeters.toInt()},${position.latitude},${position.longitude});
  way["amenity"="fuel"](around:${_nearbyRadiusMeters.toInt()},${position.latitude},${position.longitude});
  node["amenity"="truck_stop"](around:${_nearbyRadiusMeters.toInt()},${position.latitude},${position.longitude});
  way["amenity"="truck_stop"](around:${_nearbyRadiusMeters.toInt()},${position.latitude},${position.longitude});
  node["amenity"="sanitary_dump_station"](around:${_nearbyRadiusMeters.toInt()},${position.latitude},${position.longitude});
  way["amenity"="sanitary_dump_station"](around:${_nearbyRadiusMeters.toInt()},${position.latitude},${position.longitude});
  node["tourism"="information"]["information"="visitor_centre"](around:${_nearbyRadiusMeters.toInt()},${position.latitude},${position.longitude});
  way["tourism"="information"]["information"="visitor_centre"](around:${_nearbyRadiusMeters.toInt()},${position.latitude},${position.longitude});
  node["tourism"="information"](around:${_nearbyRadiusMeters.toInt()},${position.latitude},${position.longitude});
  way["tourism"="information"](around:${_nearbyRadiusMeters.toInt()},${position.latitude},${position.longitude});
);
out center 80;
''';

      const endpoints = [
        'https://overpass-api.de/api/interpreter',
        'https://overpass.kumi.systems/api/interpreter',
        'https://lz4.overpass-api.de/api/interpreter',
      ];

      http.Response? response;
      Object? lastError;

      for (final endpoint in endpoints) {
        try {
          final candidate = await http
              .post(
                Uri.parse(endpoint),
                headers: const {
                  'User-Agent': 'rvapp_1/1.0 nearby-search',
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: {'data': query},
              )
              .timeout(const Duration(seconds: 12));

          if (candidate.statusCode == 200) {
            response = candidate;
            break;
          }

          lastError = 'HTTP ${candidate.statusCode} from $endpoint';
        } catch (e) {
          lastError = e;
        }
      }

      if (response == null) {
        throw Exception('Nearby search failed on all providers. Last error: $lastError');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = (data['elements'] as List<dynamic>? ?? const []);

      final parsed = <Map<String, dynamic>>[];
      for (final raw in elements) {
        if (raw is! Map<String, dynamic>) {
          continue;
        }

        final tags = (raw['tags'] as Map?)?.cast<String, dynamic>() ?? {};
        final nameTag = tags['name']?.toString().toLowerCase() ?? '';
        final tourism = tags['tourism']?.toString();
        final information = tags['information']?.toString();
        final highway = tags['highway']?.toString();
        final amenity = tags['amenity']?.toString();

        final isCamping = tourism == 'camp_site' || tourism == 'caravan_site';
        final isRestStop = highway == 'rest_area';
        final isTravelCenter =
          highway == 'services' || amenity == 'truck_stop' || amenity == 'fuel';
        final isGuestCenter =
          (tourism == 'information' && information == 'visitor_centre') ||
          nameTag.contains('visitor center') ||
          nameTag.contains('visitor centre') ||
          nameTag.contains('guest center') ||
          nameTag.contains('guest centre');
        final isRvService =
          amenity == 'sanitary_dump_station' ||
          nameTag.contains('rv') ||
          nameTag.contains('motorhome') ||
          nameTag.contains('camper');

        if (!isCamping && !isRestStop && !isTravelCenter && !isGuestCenter && !isRvService) {
          continue;
        }

        final lat = (raw['lat'] as num?)?.toDouble() ??
            ((raw['center'] as Map?)?['lat'] as num?)?.toDouble();
        final lon = (raw['lon'] as num?)?.toDouble() ??
            ((raw['center'] as Map?)?['lon'] as num?)?.toDouble();

        if (lat == null || lon == null) {
          continue;
        }

        String type;
        String fallbackName;
        if (isCamping) {
          type = 'Camping';
          fallbackName = 'Nearby Campground';
        } else if (isGuestCenter) {
          type = 'Guest Center';
          fallbackName = 'Nearby Visitor Center';
        } else if (isRvService) {
          type = 'RV Service';
          fallbackName = 'Nearby RV Service';
        } else if (isTravelCenter) {
          type = 'Travel Center';
          fallbackName = 'Nearby Travel Center';
        } else {
          type = 'Rest Stop';
          fallbackName = 'Nearby Rest Stop';
        }

        final name = (tags['name']?.toString().trim().isNotEmpty ?? false)
            ? tags['name'].toString().trim()
            : fallbackName;

        final addressParts = [
          tags['addr:full'],
          tags['addr:housenumber'],
          tags['addr:street'],
          tags['addr:city'],
          tags['addr:state'],
          tags['addr:postcode'],
        ]
            .whereType<dynamic>()
            .map((part) => part.toString().trim())
            .where((part) => part.isNotEmpty)
            .toList();

        final distanceKm = calculateDistance(
          position.latitude,
          position.longitude,
          lat,
          lon,
        );

        parsed.add({
          'name': name,
          'type': type,
          'lat': lat,
          'lon': lon,
          'address': addressParts.isEmpty ? null : addressParts.join(', '),
          'distance': distanceKm,
        });
      }

      parsed.sort((a, b) =>
          (a['distance'] as double).compareTo(b['distance'] as double));

      var addedCount = 0;
      for (final place in parsed.take(30)) {
        final lat = place['lat'] as double;
        final lon = place['lon'] as double;
        final name = place['name'] as String;
        final type = place['type'] as String;

        final existsNearby = widget.locationManager.locations.any((location) {
          final distanceKm = calculateDistance(
            location.latitude,
            location.longitude,
            lat,
            lon,
          );
          return distanceKm < 0.15 && location.type == type;
        });

        if (existsNearby) {
          continue;
        }

        widget.locationManager.addRVLocation(
          name,
          type,
          lat,
          lon,
          'OpenStreetMap',
          address: place['address'] as String?,
        );
        addedCount++;
      }

      if (addedCount > 0) {
        widget.onUpdate();
      }

      if (mounted) {
        setState(() {
          _nearbyLoaded = true;
          _loadingNearby = false;
          _lastNearbyFetchPosition = position;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingNearby = false;
          _nearbyError = 'Could not load nearby travel locations: $e';
        });
      }
    }
  }

  Future<void> _refreshNearbyIfMoved() async {
    try {
      final latestPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () => _userLocation!,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _userLocation = latestPosition;
      });

      final baseline = _lastNearbyFetchPosition;
      if (baseline == null) {
        await _loadNearbyPlaces(latestPosition, forceRefresh: true);
        return;
      }

      final movedKm = calculateDistance(
        baseline.latitude,
        baseline.longitude,
        latestPosition.latitude,
        latestPosition.longitude,
      );

      if (movedKm >= _nearbyRefreshDistanceKm) {
        await _addCurrentLocationIfMissing(latestPosition);
        await _loadNearbyPlaces(latestPosition, forceRefresh: true);
      }
    } catch (_) {
      // Keep existing nearby data if a refresh tick fails.
    }
  }

  void _setMockLocation() {
    setState(() {
      _useMockLocation = true;
      _userLocation = Position(
        latitude: mockLatitude,
        longitude: mockLongitude,
        timestamp: DateTime.now(),
        accuracy: 50,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      _loadingLocation = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    var locations = _filterType == null
        ? widget.locationManager.locations
        : widget.locationManager.locations.where((l) => l.type == _filterType).toList();

    // Sort by distance if user location is available
    if (_userLocation != null) {
      locations = List.from(locations);
      locations.sort((a, b) {
        final distanceA = calculateDistance(_userLocation!.latitude, _userLocation!.longitude, a.latitude, a.longitude);
        final distanceB = calculateDistance(_userLocation!.latitude, _userLocation!.longitude, b.latitude, b.longitude);
        return distanceA.compareTo(distanceB);
      });
    }

    // Get current user's coordinate format preference
    final currentUser = widget.locationManager.users[widget.username];
    final coordinateFormat = currentUser?.preferences.coordinateFormat ?? 'decimal';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_loadingLocation)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    height: 20,
                    child: Row(
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Getting your location...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                )
              else if (_locationError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_locationError!, style: const TextStyle(fontSize: 12, color: Colors.orange)),
                      const SizedBox(height: 6),
                      Text(
                        'Using test location (San Francisco area)',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              else if (_userLocation != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _useMockLocation 
                      ? 'Using test location - Locations sorted by distance' 
                      : 'Locations sorted by distance from your location',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              if (_loadingNearby)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Loading nearby camping, RV services, travel centers, rest stops, and guest centers...',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              if (_nearbyError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _nearbyError!,
                        style: const TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                      if (_userLocation != null)
                        TextButton.icon(
                          onPressed: () => _loadNearbyPlaces(_userLocation!, forceRefresh: true),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Retry Nearby Search'),
                        ),
                    ],
                  ),
                ),
              DropdownButton<String?>(
                value: _filterType,
                hint: const Text('Filter by Type'),
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Types')),
                  ...['Parking', 'Camping', 'Travel Center', 'RV Service', 'Rest Stop', 'Guest Center', 'Rest Area', 'Sightseeing']
                      .map((type) => DropdownMenuItem(value: type, child: Text(type))),
                ],
                onChanged: (value) => setState(() => _filterType = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: locations.isEmpty
              ? const Center(child: Text('No locations found'))
              : ListView.builder(
                  itemCount: locations.length,
                  itemBuilder: (context, index) {
                    final location = locations[index];
                    double? distance;
                    if (_userLocation != null) {
                      distance = calculateDistance(_userLocation!.latitude, _userLocation!.longitude, location.latitude, location.longitude);
                    }
                    return LocationCard(
                      location: location,
                      locationManager: widget.locationManager,
                      onUpdate: widget.onUpdate,
                      coordinateFormat: coordinateFormat,
                      distanceUnit: widget.locationManager.users[widget.username]?.preferences.distanceUnit ?? 'km',
                      distance: distance,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// Location Card Widget
class LocationCard extends StatelessWidget {
  final RVLocation location;
  final RVLocationManager locationManager;
  final VoidCallback onUpdate;
  final String coordinateFormat;
  final double? distance;
  final String distanceUnit;

  const LocationCard({
    required this.location,
    required this.locationManager,
    required this.onUpdate,
    this.coordinateFormat = 'decimal',
    this.distance,
    this.distanceUnit = 'km',
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF0F4C81);
    const mutedText = Color(0xFF637083);
    final avgRating = location.getAverageRating();
    final ratingColor = avgRating >= 4.5
        ? const Color(0xFF27AE60)
        : avgRating >= 3.5
            ? const Color(0xFFF39C12)
            : const Color(0xFFE74C3C);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LocationDetailPage(
              location: location,
              locationManager: locationManager,
              onUpdate: onUpdate,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F4C81).withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(
            color: const Color(0xFFE5EAF0),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Location name with type badge
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          location.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            location.type,
                            style: const TextStyle(
                              color: accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Rating display
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: ratingColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.star, size: 18, color: ratingColor),
                            const SizedBox(width: 4),
                            Text(
                              avgRating.toStringAsFixed(1),
                              style: TextStyle(
                                color: ratingColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${location.reviews.length}',
                          style: TextStyle(
                            color: ratingColor,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Location details - Address or MGRS based on preference
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      coordinateFormat == 'mgrs'
                          ? convertToMGRS(location.latitude, location.longitude)
                          : (location.address ?? '${location.latitude.toStringAsFixed(2)}, ${location.longitude.toStringAsFixed(2)}'),
                      style: const TextStyle(
                        color: mutedText,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.person, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    'Added by ${location.addedBy}',
                    style: const TextStyle(
                      color: mutedText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              if (distance != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.near_me, size: 16, color: accent),
                    const SizedBox(width: 6),
                    Text(
                      distanceUnit == 'miles'
                          ? '${(distance! * 0.621371).toStringAsFixed(1)} mi away'
                          : '${distance!.toStringAsFixed(1)} km away',
                      style: const TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Location Detail Page
class LocationDetailPage extends StatefulWidget {
  final RVLocation location;
  final RVLocationManager locationManager;
  final VoidCallback onUpdate;

  const LocationDetailPage({
    required this.location,
    required this.locationManager,
    required this.onUpdate,
    super.key,
  });

  @override
  State<LocationDetailPage> createState() => _LocationDetailPageState();
}

class _LocationDetailPageState extends State<LocationDetailPage> {
  final _commentController = TextEditingController();
  double _rating = 5;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.location.name)),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.location.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text('Type: ${widget.location.type}'),
                  Text('Added by: ${widget.location.addedBy}'),
                  Text('Location: (${widget.location.latitude.toStringAsFixed(4)}, ${widget.location.longitude.toStringAsFixed(4)})'),
                  if (widget.location.address != null && widget.location.address!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(widget.location.address!),
                  ],
                  if (widget.location.details != null && widget.location.details!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(widget.location.details!),
                  ],
                  _buildMediaAttachments(
                    context,
                    photos: widget.location.photos,
                    videos: widget.location.videos,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Average Rating: ${widget.location.getAverageRating().toStringAsFixed(1)}/5',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add a Review',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Rating: '),
                      Slider(
                        value: _rating,
                        min: 1,
                        max: 5,
                        divisions: 4,
                        label: _rating.toString(),
                        onChanged: (value) => setState(() => _rating = value),
                      ),
                      Text('${_rating.toInt()}/5'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _commentController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Write your review...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_commentController.text.isNotEmpty) {
                          widget.locationManager.addReviewToLocation(
                            widget.locationManager.locations.indexOf(widget.location),
                            'CurrentUser',
                            _commentController.text,
                            _rating,
                          );
                          _commentController.clear();
                          _rating = 5;
                          widget.onUpdate();
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Review added successfully!')),
                          );
                        }
                      },
                      child: const Text('Submit Review'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reviews (${widget.location.reviews.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (widget.location.reviews.isEmpty)
                    const Text('No reviews yet')
                  else
                    Column(
                      children: widget.location.reviews
                          .map(
                            (review) => Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          review.username,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        Row(
                                          children: [
                                            const Icon(Icons.star, size: 16, color: Colors.amber),
                                            Text('${review.rating.toInt()}/5'),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(review.comment),
                                    const SizedBox(height: 4),
                                    Text(
                                      review.createdDate.toString().split('.')[0],
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }
}

// Add Location Page
class AddLocationPage extends StatefulWidget {
  final RVLocationManager locationManager;
  final String username;
  final VoidCallback onUpdate;

  const AddLocationPage({
    required this.locationManager,
    required this.username,
    required this.onUpdate,
    super.key,
  });

  @override
  State<AddLocationPage> createState() => _AddLocationPageState();
}

class _AddLocationPageState extends State<AddLocationPage> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _detailsController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _photoUrlsController = TextEditingController();
  final _videoUrlsController = TextEditingController();
  String _selectedType = 'Parking';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🏕️ Share Your Discovery', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 12),
          Text(
            'Help other RV travelers by sharing amazing locations. User submissions are reviewed by admin before listing.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF95A99C),
            ),
          ),
          const SizedBox(height: 32),
          // Form Card
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1B5E4B).withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildFormField(
                  controller: _nameController,
                  label: 'Location Name',
                  icon: Icons.location_on,
                  hint: 'e.g., Beautiful Lake Campground',
                ),
                const SizedBox(height: 20),
                _buildFormField(
                  controller: _addressController,
                  label: 'Address',
                  icon: Icons.home,
                  hint: 'e.g., 1500 Broadway, New York, NY 10036',
                ),
                const SizedBox(height: 20),
                _buildFormField(
                  controller: _detailsController,
                  label: 'Notes for travelers',
                  icon: Icons.notes,
                  hint: 'Optional details about access, safety, hookups, or scenery',
                ),
                const SizedBox(height: 20),
                _buildLocationTypeDropdown(),
                const SizedBox(height: 20),
                _buildFormField(
                  controller: _latitudeController,
                  label: 'Latitude',
                  icon: Icons.map,
                  hint: 'e.g., 37.7749 (-90 to 90)',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),
                _buildFormField(
                  controller: _longitudeController,
                  label: 'Longitude',
                  icon: Icons.navigation,
                  hint: 'e.g., -122.4194 (-180 to 180)',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),
                _buildFormField(
                  controller: _photoUrlsController,
                  label: 'Photo URLs',
                  icon: Icons.photo_library,
                  hint: 'Optional photo URLs separated by commas or new lines',
                ),
                const SizedBox(height: 20),
                _buildFormField(
                  controller: _videoUrlsController,
                  label: 'Video URLs',
                  icon: Icons.videocam,
                  hint: 'Optional video URLs separated by commas or new lines',
                ),
                const SizedBox(height: 32),
                // Submit button
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1B5E4B), Color(0xFF27AE60)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1B5E4B).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _submitForm,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.check_circle, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'Submit Location',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Tips section
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1B5E4B).withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF1B5E4B).withValues(alpha: 0.1),
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.lightbulb, color: Color(0xFF1B5E4B), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Pro Tips',
                      style: TextStyle(
                        color: Color(0xFF1B5E4B),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '• Use accurate GPS coordinates\n• Include clear location names\n• Share safe, verified spots',
                  style: TextStyle(
                    color: Color(0xFF2C3E3D),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF1B5E4B)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF1B5E4B),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF5F9F7),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF1B5E4B),
                width: 0.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: const Color(0xFF1B5E4B).withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF1B5E4B),
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationTypeDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.category, size: 18, color: Color(0xFF1B5E4B)),
            SizedBox(width: 8),
            Text(
              'Location Type',
              style: TextStyle(
                color: Color(0xFF1B5E4B),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F9F7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF1B5E4B).withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: DropdownButtonFormField<String>(
            initialValue: _selectedType,
            items: ['Parking', 'Camping', 'Travel Center', 'RV Service', 'Rest Stop', 'Guest Center', 'Rest Area', 'Sightseeing']
                .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                .toList(),
            onChanged: (value) => setState(() => _selectedType = value!),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  void _submitForm() {
    if (_nameController.text.isEmpty ||
        _latitudeController.text.isEmpty ||
        _longitudeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please fill all fields'),
          backgroundColor: const Color(0xFFE74C3C),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    try {
      double lat = double.parse(_latitudeController.text);
      double lon = double.parse(_longitudeController.text);

      if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
        throw Exception('Invalid coordinates');
      }

      if (widget.username.toLowerCase() == 'admin') {
        widget.locationManager.addRVLocation(
          _nameController.text,
          _selectedType,
          lat,
          lon,
          widget.username,
          address: _addressController.text.isNotEmpty ? _addressController.text : null,
          details: _detailsController.text.trim().isNotEmpty ? _detailsController.text.trim() : null,
          photos: _parseMediaUrls(_photoUrlsController.text),
          videos: _parseMediaUrls(_videoUrlsController.text),
        );
      } else {
        widget.locationManager.submitLocationForApproval(
          _nameController.text,
          _selectedType,
          lat,
          lon,
          widget.username,
          address: _addressController.text.isNotEmpty ? _addressController.text : null,
          details: _detailsController.text.trim().isNotEmpty ? _detailsController.text.trim() : null,
          photos: _parseMediaUrls(_photoUrlsController.text),
          videos: _parseMediaUrls(_videoUrlsController.text),
        );
      }

      _nameController.clear();
      _addressController.clear();
      _detailsController.clear();
      _latitudeController.clear();
      _longitudeController.clear();
      _photoUrlsController.clear();
      _videoUrlsController.clear();
      _selectedType = 'Parking';
      widget.onUpdate();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.username.toLowerCase() == 'admin'
                ? '✅ Location added successfully!'
                : '✅ Location submitted for admin approval.',
          ),
          backgroundColor: const Color(0xFF27AE60),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'Invalid input. Please check coordinates.'),
          backgroundColor: const Color(0xFFE74C3C),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _detailsController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _photoUrlsController.dispose();
    _videoUrlsController.dispose();
    super.dispose();
  }
}

// Search Page
class SearchPage extends StatefulWidget {
  final RVLocationManager locationManager;
  final VoidCallback onUpdate;

  const SearchPage({required this.locationManager, required this.onUpdate, super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _searchController = TextEditingController();
  List<RVLocation> _searchResults = [];

  void _search(String query) {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() {
      _searchResults = widget.locationManager.locations
          .where((location) => location.name.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search locations...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: _search,
          ),
        ),
        Expanded(
          child: _searchResults.isEmpty
              ? Center(
                  child: Text(_searchController.text.isEmpty ? 'Enter a search term' : 'No results found'),
                )
              : ListView.builder(
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final location = _searchResults[index];
                    return LocationCard(
                      location: location,
                      locationManager: widget.locationManager,
                      onUpdate: widget.onUpdate,
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

// User Profile Page
class UserProfilePage extends StatefulWidget {
  final RVLocationManager locationManager;
  final String username;
  final VoidCallback onUpdate;

  const UserProfilePage({
    required this.locationManager,
    required this.username,
    required this.onUpdate,
    super.key,
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late TextEditingController _makeController;
  late TextEditingController _modelController;
  late TextEditingController _yearController;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    final user = widget.locationManager.users[widget.username];
    _makeController = TextEditingController(text: user?.rvMake ?? '');
    _modelController = TextEditingController(text: user?.rvModel ?? '');
    _yearController = TextEditingController(text: user?.rvYear ?? '');
  }

  void _saveRVInfo() {
    final user = widget.locationManager.users[widget.username];
    if (user != null) {
      user.updateRVInfo(
        _makeController.text,
        _modelController.text,
        _yearController.text,
      );
      widget.onUpdate();
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('RV information updated successfully!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.locationManager.users[widget.username];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User Info Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.orange[200],
                        ),
                        child: Center(
                          child: Text(
                            widget.username[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.username,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Locations Added: ${user?.locationsAdded ?? 0}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              'Reviews: ${user?.reviews.length ?? 0}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // RV Information Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'My RV',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              ElevatedButton.icon(
                onPressed: () => setState(() => _isEditing = !_isEditing),
                icon: Icon(_isEditing ? Icons.close : Icons.edit),
                label: Text(_isEditing ? 'Cancel' : 'Edit'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (!_isEditing && user?.rvMake == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.rv_hookup, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(
                      'No RV Information Added',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add your RV make and model to help other travelers!',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
          else if (!_isEditing)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.rv_hookup, color: Colors.orange),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${user?.rvYear ?? 'N/A'} ${user?.rvMake ?? 'Unknown'} ${user?.rvModel ?? ''}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          if (_isEditing) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _makeController,
              decoration: const InputDecoration(
                labelText: 'RV Make',
                hintText: 'e.g., Winnebago, Forest River, Thor',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.business),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: 'RV Model',
                hintText: 'e.g., Minnie Winnie, Salem, Palazzo',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.drive_eta),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _yearController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Year',
                hintText: 'e.g., 2023',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.calendar_today),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveRVInfo,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Save RV Information'),
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Stats Section
          Text(
            'Stats',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'Locations Added',
                  value: '${user?.locationsAdded ?? 0}',
                  icon: Icons.location_on,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  title: 'Reviews Written',
                  value: '${user?.reviews.length ?? 0}',
                  icon: Icons.star,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if ((user?.reviews.length ?? 0) > 0)
            _StatCard(
              title: 'Average Rating',
              value: user!.reviews.isNotEmpty
                  ? (user.reviews.fold(0.0, (sum, r) => sum + r.rating) / user.reviews.length)
                      .toStringAsFixed(1)
                  : 'N/A',
              icon: Icons.favorite,
              color: Colors.red,
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    super.dispose();
  }
}

// Stat Card Widget
class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Map & Weather Page
class MapWeatherPage extends StatefulWidget {
  final RVLocationManager locationManager;
  final String username;

  const MapWeatherPage({
    required this.locationManager,
    required this.username,
    super.key,
  });

  @override
  State<MapWeatherPage> createState() => _MapWeatherPageState();
}

class _MapWeatherPageState extends State<MapWeatherPage> {
  Position? _currentPosition;
  bool _loadingPosition = true;
  String? _locationError;
  String _resolvedLocationLabel = 'Current area';
  bool _loadingWeather = false;
  String? _weatherError;
  String _weatherSummary = 'Loading weather...';
  double? _temperatureF;
  double? _feelsLikeF;
  double? _windMph;
  int? _humidityPercent;
  int? _rainChancePercent;

  @override
  void initState() {
    super.initState();
    _loadCurrentPosition();
  }

  Future<void> _loadCurrentPosition() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) {
          setState(() {
            _locationError = 'Location services are disabled.';
            _loadingPosition = false;
          });
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        if (mounted) {
          setState(() {
            _locationError = 'Location permission is not granted.';
            _loadingPosition = false;
          });
        }
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _locationError = 'Location permission is permanently denied. Open settings to allow location access.';
            _loadingPosition = false;
          });
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 8));

      String resolvedLabel = 'Current area';
      try {
        final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final parts = <String>[
            if ((place.locality ?? '').trim().isNotEmpty) place.locality!.trim(),
            if ((place.administrativeArea ?? '').trim().isNotEmpty) place.administrativeArea!.trim(),
          ];
          if (parts.isNotEmpty) {
            resolvedLabel = parts.join(', ');
          }
        }
      } catch (_) {
        // Keep fallback label if reverse geocoding fails.
      }

      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _resolvedLocationLabel = resolvedLabel;
          _loadingPosition = false;
          _locationError = null;
        });
      }

      await _loadWeatherForPosition(pos);
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationError = 'Could not get current location: $e';
          _loadingPosition = false;
        });
      }
    }
  }

  Future<void> _loadWeatherForPosition(Position pos) async {
    if (mounted) {
      setState(() {
        _loadingWeather = true;
        _weatherError = null;
      });
    }

    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${pos.latitude}'
        '&longitude=${pos.longitude}'
        '&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,precipitation_probability',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Weather request failed (${response.statusCode})');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final current = data['current'] as Map<String, dynamic>?;
      if (current == null) {
        throw Exception('Weather data missing current values');
      }

      final tempC = (current['temperature_2m'] as num?)?.toDouble();
      final feelsC = (current['apparent_temperature'] as num?)?.toDouble();
      final windKmh = (current['wind_speed_10m'] as num?)?.toDouble();
      final humidity = (current['relative_humidity_2m'] as num?)?.toInt();
      final rainChance = (current['precipitation_probability'] as num?)?.toInt();
      final weatherCode = (current['weather_code'] as num?)?.toInt();

      if (mounted) {
        setState(() {
          _temperatureF = tempC == null ? null : (tempC * 9 / 5) + 32;
          _feelsLikeF = feelsC == null ? null : (feelsC * 9 / 5) + 32;
          _windMph = windKmh == null ? null : (windKmh * 0.621371);
          _humidityPercent = humidity;
          _rainChancePercent = rainChance;
          _weatherSummary = _describeWeatherCode(weatherCode);
          _loadingWeather = false;
          _weatherError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingWeather = false;
          _weatherError = 'Could not load live weather: $e';
          _weatherSummary = 'Weather unavailable';
        });
      }
    }
  }

  String _describeWeatherCode(int? code) {
    switch (code) {
      case 0:
        return 'Clear sky';
      case 1:
      case 2:
      case 3:
        return 'Partly cloudy';
      case 45:
      case 48:
        return 'Foggy';
      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
        return 'Drizzle';
      case 61:
      case 63:
      case 65:
      case 66:
      case 67:
      case 80:
      case 81:
      case 82:
        return 'Rain';
      case 71:
      case 73:
      case 75:
      case 77:
      case 85:
      case 86:
        return 'Snow';
      case 95:
      case 96:
      case 99:
        return 'Thunderstorm';
      default:
        return 'Partly cloudy';
    }
  }

  String _windAlertText() {
    if (_windMph == null) {
      return 'No live wind alert data available for your current position.';
    }
    if (_windMph! >= 30) {
      return 'High wind warning near $_resolvedLocationLabel. Drive with extra caution.';
    }
    if (_windMph! >= 20) {
      return 'Strong wind gusts expected near $_resolvedLocationLabel this evening.';
    }
    return 'No severe wind alerts near $_resolvedLocationLabel right now.';
  }

  LatLng _initialCenter() {
    if (_currentPosition != null) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }
    if (widget.locationManager.locations.isNotEmpty) {
      final first = widget.locationManager.locations.first;
      return LatLng(first.latitude, first.longitude);
    }
    return const LatLng(39.8283, -98.5795);
  }

  String _currentCoordinatesLabel() {
    if (_currentPosition == null) {
      return 'Locating your coordinates...';
    }
    return '${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}';
  }

  String _currentLocationLabel() {
    if (_currentPosition == null) {
      return 'Detecting your location...';
    }
    return _resolvedLocationLabel;
  }

  List<MapEntry<RVLocation, double>> _nearestLocations() {
    if (_currentPosition == null) {
      return const [];
    }

    final ranked = widget.locationManager.locations
        .map(
          (location) => MapEntry(
            location,
            calculateDistance(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              location.latitude,
              location.longitude,
            ),
          ),
        )
        .toList();

    ranked.sort((a, b) => a.value.compareTo(b.value));
    return ranked.take(3).toList();
  }

  String _formatDistance(double km) {
    if (km < 1) {
      return '${(km * 1000).round()} m away';
    }
    return '${km.toStringAsFixed(1)} km away';
  }

  @override
  Widget build(BuildContext context) {
    final center = _initialCenter();
    final currentLocationLabel = _currentLocationLabel();
    final currentCoordinatesLabel = _currentCoordinatesLabel();
    final nearest = _nearestLocations();
    final markers = <Marker>[
      if (_currentPosition != null)
        Marker(
          point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          width: 32,
          height: 32,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F4C81),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.my_location, color: Colors.white, size: 16),
          ),
        ),
      ...widget.locationManager.locations.take(80).map(
            (location) => Marker(
              point: LatLng(location.latitude, location.longitude),
              width: 30,
              height: 30,
              child: Tooltip(
                message: '${location.name}\n${location.type}',
                child: Icon(
                  (location.type == 'Rest Area' || location.type == 'Rest Stop' || location.type == 'Travel Center')
                      ? Icons.local_gas_station
                      : (location.type == 'Guest Center' ? Icons.info : Icons.terrain),
                  color: (location.type == 'Rest Area' || location.type == 'Rest Stop' || location.type == 'Travel Center')
                      ? const Color(0xFFEF6C00)
                      : (location.type == 'Guest Center' ? const Color(0xFF1565C0) : const Color(0xFF2E7D32)),
                  size: 24,
                ),
              ),
            ),
          ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Map & Real-Time Conditions',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),

          // Active map section
          Card(
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 320,
              child: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: _currentPosition != null ? 11.5 : 4.2,
                      minZoom: 3,
                      maxZoom: 18,
                    ),
                    children: [
                      TileLayer(
                        // OpenTopoMap: terrain + roadways for travel view.
                        urlTemplate: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.rvapp1',
                      ),
                      MarkerLayer(markers: markers),
                    ],
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Terrain + Roads',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (_loadingPosition)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x33000000),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_locationError != null) ...[
            const SizedBox(height: 8),
            Text(
              _locationError!,
              style: const TextStyle(fontSize: 12, color: Colors.orange),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _loadCurrentPosition,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Refresh Location'),
                ),
                OutlinedButton.icon(
                  onPressed: Geolocator.openAppSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text('Open Settings'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),

          // Current Location Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.red, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Current Location', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(
                              currentLocationLabel,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _loadCurrentPosition,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh current location',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _currentPosition == null
                        ? 'Using nearest known map center.'
                        : 'Coordinates: $currentCoordinatesLabel',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Weather Section
          Text(
            'Weather Conditions',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Live context for $currentLocationLabel',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.cloud, size: 40, color: Colors.orange),
                          const SizedBox(height: 8),
                          Text(_weatherSummary, style: Theme.of(context).textTheme.bodyMedium),
                          if (_weatherError != null)
                            Text(
                              'Live data unavailable',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange),
                            ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _temperatureF == null ? '--' : '${_temperatureF!.round()}°F',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          Text(
                            _feelsLikeF == null ? 'Feels like --' : 'Feels like ${_feelsLikeF!.round()}°F',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Conditions', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text('📍 Area: $currentLocationLabel'),
                        Text(_windMph == null ? '💨 Wind: --' : '💨 Wind: ${_windMph!.round()} mph'),
                        Text(_humidityPercent == null ? '💧 Humidity: --' : '💧 Humidity: $_humidityPercent%'),
                        Text('☀️ UV Index: --'),
                        Text(_rainChancePercent == null ? '🌧️ Chance of Rain: --' : '🌧️ Chance of Rain: $_rainChancePercent%'),
                        if (_loadingWeather)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Road Conditions Section
          Text(
            'Road Conditions',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Nearest travel points from your current position',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (nearest.isEmpty)
                    Text(
                      'Need your current location to calculate nearby road points.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    ...nearest.asMap().entries.map((entry) {
                      final item = entry.value;
                      final location = item.key;
                      final distanceKm = item.value;
                      final isServiceStop = location.type == 'Rest Area' ||
                          location.type == 'Rest Stop' ||
                          location.type == 'Travel Center';
                      final isGuestCenter = location.type == 'Guest Center';

                      return Padding(
                        padding: EdgeInsets.only(bottom: entry.key == nearest.length - 1 ? 0 : 12),
                        child: _RoadConditionItem(
                          route: location.name,
                          distanceLabel: _formatDistance(distanceKm),
                          status: isServiceStop
                              ? 'Open'
                              : (isGuestCenter ? 'Open' : 'Accessible'),
                          statusColor: isServiceStop
                              ? Colors.green
                              : (isGuestCenter ? Colors.blue : Colors.orange),
                          icon: isServiceStop
                              ? Icons.local_gas_station
                              : (isGuestCenter ? Icons.info : Icons.terrain),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Alerts Section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Weather Alert', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text(_windAlertText(), style: Theme.of(context).textTheme.bodySmall),
                    ],
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

class _RoadConditionItem extends StatelessWidget {
  final String route;
  final String distanceLabel;
  final String status;
  final Color statusColor;
  final IconData icon;

  const _RoadConditionItem({
    required this.route,
    required this.distanceLabel,
    required this.status,
    required this.statusColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(route, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
            Text(distanceLabel, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        Row(
          children: [
            Icon(icon, color: statusColor, size: 20),
            const SizedBox(width: 8),
            Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }
}

// Dashboard Page - Dashboard with user stats and quick access
class DashboardPage extends StatefulWidget {
  final RVLocationManager locationManager;
  final String username;
  final VoidCallback onUpdate;

  const DashboardPage({
    required this.locationManager,
    required this.username,
    required this.onUpdate,
    super.key,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  Widget build(BuildContext context) {
    final user = widget.locationManager.users[widget.username];

    if (user == null) {
      return const Center(child: Text('User not found'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome Banner
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1B5E4B), Color(0xFF2d8c7e)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back, ${user.username}!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  user.bio ?? 'Add a bio to your profile',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),

          // Profile Picture
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF1B5E4B),
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: user.profilePicture != null
                ? ClipOval(child: Image.network(user.profilePicture!, fit: BoxFit.cover, errorBuilder: (_, _, _) {
                    return Center(child: Text(user.username[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)));
                  }))
                : Center(child: Text(user.username[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold))),
            ),
          ),

          const SizedBox(height: 24),

          // Stats Grid
          Text('Your Stats', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              _buildStatCard(
                context,
                icon: Icons.location_on,
                label: 'Locations Added',
                value: user.locationsAdded.toString(),
                color: Color(0xFF1B5E4B),
              ),
              _buildStatCard(
                context,
                icon: Icons.people,
                label: 'Followers',
                value: user.followers.length.toString(),
                color: Color(0xFF2d8c7e),
              ),
              _buildStatCard(
                context,
                icon: Icons.person_add,
                label: 'Following',
                value: user.following.length.toString(),
                color: Color(0xFF1B5E4B),
              ),
              _buildStatCard(
                context,
                icon: Icons.explore,
                label: 'Posts',
                value: user.adventures.length.toString(),
                color: Color(0xFF2d8c7e),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // RV Info Section
          if (user.rvMake != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your RV', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Color(0xFFF5F9F7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Color(0xFF1B5E4B).withValues(alpha: 0.2)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Color(0xFF1B5E4B),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.directions_car, color: Colors.white, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${user.rvYear} ${user.rvMake}', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                            Text(user.rvModel ?? '', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),

          // Quick Actions
          Text('Quick Access', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    // Navigate to locations - would need to be handled by parent
                  },
                  child: _buildQuickActionCard(
                    context,
                    icon: Icons.location_on,
                    label: 'Browse\nLocations',
                    color: Color(0xFF1B5E4B),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    // Navigate to map - would need to be handled by parent
                  },
                  child: _buildQuickActionCard(
                    context,
                    icon: Icons.map,
                    label: 'View\nMap',
                    color: Color(0xFF2d8c7e),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    // Navigate to social - would need to be handled by parent
                  },
                  child: _buildQuickActionCard(
                    context,
                    icon: Icons.people,
                    label: 'Check\nSocial',
                    color: Color(0xFF1B5E4B),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, {required IconData icon, required String label, required String value, required Color color}) {
    return Container(
      decoration: BoxDecoration(
        color: Color(0xFFF5F9F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard(BuildContext context, {required IconData icon, required String label, required Color color}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: Colors.white),
          const SizedBox(height: 8),
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// Social Page - Feed-first posting and pin drops
class SocialPage extends StatefulWidget {
  final RVLocationManager locationManager;
  final String username;
  final VoidCallback onUpdate;

  const SocialPage({
    required this.locationManager,
    required this.username,
    required this.onUpdate,
    super.key,
  });

  @override
  State<SocialPage> createState() => _SocialPageState();
}

class _SocialPageState extends State<SocialPage> {
  @override
  Widget build(BuildContext context) {
    final currentUser = widget.locationManager.users[widget.username];
    if (currentUser == null) {
      return const Center(child: Text('User not found'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Social Feed', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    'See the latest updates and share posts or pin drops with photos and videos.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _showPostUpdateDialog,
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E4B)),
                        icon: const Icon(Icons.edit, color: Colors.white),
                        label: const Text('Post Update', style: TextStyle(color: Colors.white)),
                      ),
                      ElevatedButton.icon(
                        onPressed: _showPinDropDialog,
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF6C00)),
                        icon: const Icon(Icons.add_location_alt, color: Colors.white),
                        label: const Text('Submit Pin Drop', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: _buildFeed(currentUser)),
      ],
    );
  }

  Widget _buildFeed(RVUser currentUser) {
    final posts = widget.locationManager.users.values
        .expand(
          (user) => user.adventures.map(
            (post) => _SocialFeedEntry(username: user.username, post: post),
          ),
        )
        .toList()
      ..sort((a, b) => b.post.date.compareTo(a.post.date));

    final pendingPinDrops = widget.locationManager.pendingLocationSubmissions
        .where((submission) => submission.submittedBy == widget.username)
        .length;

    if (posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.dynamic_feed, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            Text('No updates yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Post an update or submit a pin drop to get the feed started.', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF1B5E4B).withValues(alpha: 0.12),
                  child: const Icon(Icons.dynamic_feed, color: Color(0xFF1B5E4B)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Community Feed', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '${posts.length} posts • $pendingPinDrops pending pin drop${pendingPinDrops == 1 ? '' : 's'} from you',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        ...posts.map(_buildFeedCard),
      ],
    );
  }

  Widget _buildFeedCard(_SocialFeedEntry entry) {
    final post = entry.post;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: () => _showUserMiniProfile(entry.username),
                  borderRadius: BorderRadius.circular(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.orange[200],
                        child: Text(entry.username[0].toUpperCase()),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(post.date.toString().split(' ')[0], style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _showUserMiniProfile(entry.username),
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'View profile',
                ),
              ],
            ),
            if (post.isLocationSubmission) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.push_pin, size: 18, color: Color(0xFF1B5E4B)),
                    label: const Text('Pin drop submitted'),
                    backgroundColor: const Color(0xFFF5F9F7),
                  ),
                  if (post.locationType != null) Chip(label: Text(post.locationType!)),
                ],
              ),
            ],
            if (post.title.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(post.title, style: Theme.of(context).textTheme.titleMedium),
            ],
            const SizedBox(height: 8),
            Text(post.description),
            if (post.locationName.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(post.locationName, style: Theme.of(context).textTheme.bodySmall),
                  ),
                ],
              ),
            ],
            if (post.latitude != null && post.longitude != null) ...[
              const SizedBox(height: 8),
              Text(
                '${post.latitude!.toStringAsFixed(4)}, ${post.longitude!.toStringAsFixed(4)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (!post.isLocationSubmission && post.rating > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    Icons.star,
                    size: 16,
                    color: i < post.rating.toInt() ? Colors.amber : Colors.grey[300],
                  ),
                ),
              ),
            ],
            _buildMediaAttachments(context, photos: post.photos, videos: post.videos),
          ],
        ),
      ),
    );
  }

  void _showPostUpdateDialog() {
    final currentUser = widget.locationManager.users[widget.username];
    if (currentUser == null) {
      return;
    }

    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final locationController = TextEditingController();
    final photoUrlsController = TextEditingController();
    final videoUrlsController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Post Update'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Headline',
                    border: OutlineInputBorder(),
                    hintText: 'Sunset at the lake',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Update',
                    border: OutlineInputBorder(),
                    hintText: 'Share what is happening on the road...',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    border: OutlineInputBorder(),
                    hintText: 'Optional',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: photoUrlsController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Photo URLs',
                    border: OutlineInputBorder(),
                    hintText: 'Optional photo URLs separated by commas or new lines',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: videoUrlsController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Video URLs',
                    border: OutlineInputBorder(),
                    hintText: 'Optional video URLs separated by commas or new lines',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final headline = titleController.text.trim();
                final description = descriptionController.text.trim();
                final locationName = locationController.text.trim();

                if (description.isEmpty) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: Text('Add some text to your update.')),
                  );
                  return;
                }

                currentUser.addAdventure(
                  Adventure(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: headline.isEmpty ? 'Status Update' : headline,
                    description: description,
                    locationName: locationName,
                    date: DateTime.now(),
                    photos: _parseMediaUrls(photoUrlsController.text),
                    videos: _parseMediaUrls(videoUrlsController.text),
                    rating: 0,
                  ),
                );

                widget.onUpdate();
                Navigator.pop(context);
                setState(() {});

                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Update posted!')),
                );
              },
              child: const Text('Post'),
            ),
          ],
        );
      },
    );
  }

  void _showPinDropDialog() {
    final currentUser = widget.locationManager.users[widget.username];
    if (currentUser == null) {
      return;
    }

    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final notesController = TextEditingController();
    final latitudeController = TextEditingController();
    final longitudeController = TextEditingController();
    final photoUrlsController = TextEditingController();
    final videoUrlsController = TextEditingController();
    String selectedType = 'Parking';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Submit Pin Drop'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Location Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedType,
                      items: ['Parking', 'Camping', 'Travel Center', 'RV Service', 'Rest Stop', 'Guest Center', 'Rest Area', 'Sightseeing']
                          .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedType = value);
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Location Type',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressController,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: latitudeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Latitude',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: longitudeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Longitude',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        border: OutlineInputBorder(),
                        hintText: 'Optional details for travelers and reviewers',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: photoUrlsController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Photo URLs',
                        border: OutlineInputBorder(),
                        hintText: 'Optional photo URLs separated by commas or new lines',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: videoUrlsController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Video URLs',
                        border: OutlineInputBorder(),
                        hintText: 'Optional video URLs separated by commas or new lines',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final address = addressController.text.trim();
                    final notes = notesController.text.trim();

                    if (name.isEmpty || latitudeController.text.trim().isEmpty || longitudeController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(content: Text('Name and coordinates are required.')),
                      );
                      return;
                    }

                    try {
                      final latitude = double.parse(latitudeController.text.trim());
                      final longitude = double.parse(longitudeController.text.trim());
                      final photos = _parseMediaUrls(photoUrlsController.text);
                      final videos = _parseMediaUrls(videoUrlsController.text);

                      widget.locationManager.submitLocationForApproval(
                        name,
                        selectedType,
                        latitude,
                        longitude,
                        widget.username,
                        address: address.isEmpty ? null : address,
                        details: notes.isEmpty ? null : notes,
                        photos: photos,
                        videos: videos,
                      );

                      currentUser.addAdventure(
                        Adventure(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          title: name,
                          description: notes.isEmpty ? 'Submitted a $selectedType pin drop for review.' : notes,
                          locationName: address.isEmpty ? name : address,
                          date: DateTime.now(),
                          photos: photos,
                          videos: videos,
                          rating: 0,
                          isLocationSubmission: true,
                          locationType: selectedType,
                          latitude: latitude,
                          longitude: longitude,
                        ),
                      );

                      widget.onUpdate();
                      Navigator.pop(context);
                      setState(() {});

                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(content: Text('Pin drop submitted for review.')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text(
                            e is Exception
                                ? e.toString().replaceFirst('Exception: ', '')
                                : 'Invalid location submission.',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showUserMiniProfile(String profileUsername) {
    final profileUser = widget.locationManager.users[profileUsername];
    final currentUser = widget.locationManager.users[widget.username];

    if (profileUser == null || currentUser == null) {
      return;
    }

    final isOwnProfile = profileUsername == widget.username;
    final isFollowing = currentUser.following.contains(profileUsername);
    final hasPendingRequest = profileUser.followRequests.contains(widget.username);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.orange[200],
                child: Text(profileUser.username[0].toUpperCase()),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(profileUser.username)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (profileUser.bio != null && profileUser.bio!.trim().isNotEmpty)
                Text(profileUser.bio!)
              else
                Text('No bio yet.', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              Text('${profileUser.locationsAdded} locations • ${profileUser.adventures.length} posts'),
              const SizedBox(height: 6),
              Text('${profileUser.followers.length} followers • ${profileUser.following.length} following'),
              const SizedBox(height: 8),
              Text(
                profileUser.preferences.requireFollowApproval
                    ? 'Profile: Follow approval required'
                    : 'Profile: Open follow',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            if (!isOwnProfile)
              TextButton(
                onPressed: () {
                  if (isFollowing) {
                    currentUser.unfollowUser(profileUsername);
                    profileUser.removeFollower(widget.username);
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text('Unfollowed @${profileUser.username}')),
                    );
                  } else if (hasPendingRequest) {
                    profileUser.removeFollowRequest(widget.username);
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text('Cancelled request to @${profileUser.username}')),
                    );
                  } else if (profileUser.preferences.requireFollowApproval) {
                    profileUser.addFollowRequest(widget.username);
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text('Follow request sent to @${profileUser.username}')),
                    );
                  } else {
                    currentUser.followUser(profileUsername);
                    profileUser.addFollower(widget.username);
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text('Now following @${profileUser.username}')),
                    );
                  }

                  widget.onUpdate();
                  if (mounted) {
                    setState(() {});
                  }
                  Navigator.pop(context);
                },
                child: Text(
                  isFollowing
                      ? 'Unfollow'
                      : hasPendingRequest
                          ? 'Cancel Request'
                          : profileUser.preferences.requireFollowApproval
                              ? 'Request Follow'
                              : 'Follow',
                ),
              ),
          ],
        );
      },
    );
  }

}

// Settings Page
class SettingsPage extends StatefulWidget {
  final RVLocationManager locationManager;
  final String username;
  final VoidCallback onUpdate;

  const SettingsPage({
    required this.locationManager,
    required this.username,
    required this.onUpdate,
    super.key,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final user = widget.locationManager.users[widget.username];
    final prefs = user?.preferences;

    if (prefs == null) {
      return const Center(child: Text('User not found'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile Section at Top
          _buildProfileSection(user!),
          
          const SizedBox(height: 32),
          
          Text('User Preferences', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),

          // Notifications Section
          Text('Notifications', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Weather Alerts'),
            subtitle: const Text('Get notified about severe weather'),
            value: prefs.showWeatherAlerts,
            onChanged: (value) {
              setState(() => prefs.showWeatherAlerts = value);
              widget.onUpdate();
            },
          ),
          SwitchListTile(
            title: const Text('Road Conditions'),
            subtitle: const Text('Alerts about traffic and road closures'),
            value: prefs.showRoadConditions,
            onChanged: (value) {
              setState(() => prefs.showRoadConditions = value);
              widget.onUpdate();
            },
          ),
          const SizedBox(height: 20),

          // Privacy Section
          Text('Privacy & Sharing', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Share My Location'),
            subtitle: const Text('Allow followers to see my current location'),
            value: prefs.shareLocation,
            onChanged: (value) {
              setState(() => prefs.shareLocation = value);
              widget.onUpdate();
            },
          ),
          SwitchListTile(
            title: const Text('Allow Messages'),
            subtitle: const Text('Allow other users to message you'),
            value: prefs.allowMessages,
            onChanged: (value) {
              setState(() => prefs.allowMessages = value);
              widget.onUpdate();
            },
          ),
          SwitchListTile(
            title: const Text('Require Follow Requests'),
            subtitle: const Text('When on, users must request approval before following you'),
            value: prefs.requireFollowApproval,
            onChanged: (value) {
              setState(() => prefs.requireFollowApproval = value);
              widget.onUpdate();
            },
          ),
          if (user.followRequests.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildFollowRequestsSection(user),
          ],
          if (widget.username.toLowerCase() == 'admin') ...[
            const SizedBox(height: 12),
            _buildPendingLocationApprovalSection(),
          ],
          const SizedBox(height: 20),

          // Map Preferences
          Text('Map Settings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: prefs.preferredMap,
            items: ['standard', 'satellite', 'terrain']
                .map((map) => DropdownMenuItem(value: map, child: Text(map.capitalize())))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => prefs.preferredMap = value);
                widget.onUpdate();
              }
            },
            decoration: const InputDecoration(
              labelText: 'Map View',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          // Coordinate Format Settings
          Text('Coordinate Format', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: prefs.coordinateFormat,
            items: ['decimal', 'mgrs']
                .map((format) {
                  final displayNames = {
                    'decimal': 'Decimal Coordinates + Address',
                    'mgrs': 'MGRS Format',
                  };
                  return DropdownMenuItem(
                    value: format,
                    child: Text(displayNames[format] ?? format),
                  );
                })
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => prefs.coordinateFormat = value);
                widget.onUpdate();
              }
            },
            decoration: const InputDecoration(
              labelText: 'Show locations as',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          // Distance Unit Settings
          Text('Distance Unit', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: prefs.distanceUnit,
            items: ['km', 'miles']
                .map((unit) {
                  final displayNames = {
                    'km': 'Kilometers (km)',
                    'miles': 'Miles (mi)',
                  };
                  return DropdownMenuItem(
                    value: unit,
                    child: Text(displayNames[unit] ?? unit),
                  );
                })
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => prefs.distanceUnit = value);
                widget.onUpdate();
              }
            },
            decoration: const InputDecoration(
              labelText: 'Distance measurement',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          // Favorite Location Types
          Text('Favorite Location Types', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ..._buildFavoriteLocationTypesCheckboxes(prefs),
          const SizedBox(height: 20),

          // Account Section
          Text('Account', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Followers'),
                      Text('${user.followers.length ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Following'),
                      Text('${user.following.length ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowRequestsSection(RVUser currentUser) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pending Follow Requests', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...currentUser.followRequests.toList().map((requesterName) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.orange[200],
                      child: Text(requesterName[0].toUpperCase(), style: const TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(requesterName)),
                    TextButton(
                      onPressed: () {
                        final requesterUser = widget.locationManager.users[requesterName];
                        requesterUser?.followUser(currentUser.username);
                        currentUser.addFollower(requesterName);
                        currentUser.removeFollowRequest(requesterName);
                        widget.onUpdate();
                        setState(() {});
                      },
                      child: const Text('Approve'),
                    ),
                    TextButton(
                      onPressed: () {
                        currentUser.removeFollowRequest(requesterName);
                        widget.onUpdate();
                        setState(() {});
                      },
                      child: const Text('Decline'),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingLocationApprovalSection() {
    final pending = widget.locationManager.pendingLocationSubmissions;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pending Location Submissions',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (pending.isEmpty)
              Text(
                'No location submissions waiting for review.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              ...pending.map((submission) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5EAF0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${submission.name} (${submission.type})',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text('Submitted by: ${submission.submittedBy}'),
                      if (submission.address != null && submission.address!.trim().isNotEmpty)
                        Text(submission.address!),
                      if (submission.details != null && submission.details!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(submission.details!),
                      ],
                      Text(
                        '${submission.latitude.toStringAsFixed(4)}, ${submission.longitude.toStringAsFixed(4)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      _buildMediaAttachments(
                        context,
                        photos: submission.photos,
                        videos: submission.videos,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () {
                              widget.locationManager.approvePendingLocation(submission.id);
                              widget.onUpdate();
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Location approved and added to directory.')),
                              );
                            },
                            child: const Text('Approve'),
                          ),
                          TextButton(
                            onPressed: () {
                              widget.locationManager.rejectPendingLocation(submission.id);
                              widget.onUpdate();
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Location submission rejected.')),
                              );
                            },
                            child: const Text('Reject'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection(RVUser currentUser) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Profile Picture
        GestureDetector(
          onTap: () => _showEditProfileDialog(currentUser),
          child: Stack(
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF1B5E4B),
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: currentUser.profilePicture != null
                  ? ClipOval(child: Image.network(currentUser.profilePicture!, fit: BoxFit.cover, errorBuilder: (_, _, _) {
                      return Center(child: Text(currentUser.username[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold)));
                    }))
                  : Center(child: Text(currentUser.username[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold))),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF1B5E4B),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.edit, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Username
        Text(currentUser.username, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
        
        // Bio
        if (currentUser.bio != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(currentUser.bio!, style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('Add a bio', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey), textAlign: TextAlign.center),
          ),
        
        const SizedBox(height: 16),

        // Stats Row
        Container(
          decoration: BoxDecoration(
            color: Color(0xFFF5F9F7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Color(0xFF1B5E4B).withValues(alpha: 0.2)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(
                children: [
                  Text(currentUser.followers.length.toString(), style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Color(0xFF1B5E4B), fontWeight: FontWeight.bold)),
                  Text('Followers', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              Container(width: 1, height: 40, color: Colors.grey[300]),
              Column(
                children: [
                  Text(currentUser.following.length.toString(), style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Color(0xFF1B5E4B), fontWeight: FontWeight.bold)),
                  Text('Following', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              Container(width: 1, height: 40, color: Colors.grey[300]),
              Column(
                children: [
                  Text(currentUser.locationsAdded.toString(), style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Color(0xFF1B5E4B), fontWeight: FontWeight.bold)),
                  Text('Locations', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Social Media Links
        if (currentUser.socials.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Social Links', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: currentUser.socials.entries.map((entry) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Color(0xFFF5F9F7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Color(0xFF1B5E4B).withValues(alpha: 0.3)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_getSocialIcon(entry.key), size: 18, color: Color(0xFF1B5E4B)),
                        const SizedBox(width: 8),
                        Text(entry.value, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
            ],
          ),


      ],
    );
  }

  IconData _getSocialIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'instagram':
        return Icons.camera_alt;
      case 'twitter':
        return Icons.share;
      case 'facebook':
        return Icons.people;
      case 'youtube':
        return Icons.play_circle;
      case 'tiktok':
        return Icons.music_note;
      default:
        return Icons.link;
    }
  }

  void _showPhotoOptions(RVUser user) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add Photo'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _showPhotoUrlDialog(user);
            },
            child: const Row(
              children: [
                Icon(Icons.link),
                SizedBox(width: 12),
                Text('Add from URL'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Photo gallery integration coming soon')),
              );
            },
            child: const Row(
              children: [
                Icon(Icons.photo_library),
                SizedBox(width: 12),
                Text('Choose from Gallery'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPhotoUrlDialog(RVUser user) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Photo URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter photo URL',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                user.addPhoto(controller.text);
                widget.onUpdate();
                Navigator.pop(context);
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Photo added!')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog(RVUser user) {
    final bioController = TextEditingController(text: user.bio ?? '');
    final profilePicController = TextEditingController(text: user.profilePicture ?? '');
    final socialPlatforms = ['Instagram', 'Twitter', 'Facebook', 'YouTube', 'TikTok'];
    final selectedPlatform = ValueNotifier<String>(socialPlatforms[0]);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: profilePicController,
                decoration: const InputDecoration(
                  labelText: 'Profile Picture URL',
                  border: OutlineInputBorder(),
                  hintText: 'https://example.com/pic.jpg',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: bioController,
                decoration: const InputDecoration(
                  labelText: 'Bio',
                  border: OutlineInputBorder(),
                  hintText: 'Tell us about your RV adventures!',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Text('Add Social Media', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: selectedPlatform,
                      builder: (context, platform, _) {
                        return DropdownButton<String>(
                          isExpanded: true,
                          value: platform,
                          items: socialPlatforms.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                          onChanged: (value) => selectedPlatform.value = value ?? platform,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Handle or URL',
                        border: OutlineInputBorder(),
                        suffix: IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            final textField = context.findRenderObject() as RenderBox?;
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              user.updateBio(bioController.text);
              if (profilePicController.text.isNotEmpty) {
                user.updateProfilePicture(profilePicController.text);
              }
              widget.onUpdate();
              Navigator.pop(context);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profile updated!')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFavoriteLocationTypesCheckboxes(UserPreferences prefs) {
    final types = ['Camping', 'Parking', 'Travel Center', 'RV Service', 'Rest Stop', 'Guest Center', 'Rest Area', 'Sightseeing'];
    return types.map((type) {
      return CheckboxListTile(
        title: Text(type),
        value: prefs.favoriteLocationTypes.contains(type),
        onChanged: (value) {
          setState(() {
            if (value ?? false) {
              if (!prefs.favoriteLocationTypes.contains(type)) {
                prefs.favoriteLocationTypes.add(type);
              }
            } else {
              prefs.favoriteLocationTypes.remove(type);
            }
          });
          widget.onUpdate();
        },
      );
    }).toList();
  }
}

// Extension for capitalize
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
