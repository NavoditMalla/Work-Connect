// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart'; // (kept per your header; not used for Base64 flow)
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WorkConnect',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const AuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Helper stream for user document
Stream<DocumentSnapshot> getUserStream(String uid) {
  return FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
}

// ---------------- ADMIN VERIFICATION PAGE ------------------
class AdminVerificationPage extends StatelessWidget {
  const AdminVerificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pending Verifications")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('verificationRequested', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final users = snapshot.data!.docs;
          if (users.isEmpty) return const Center(child: Text("No pending requests."));

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final data = users[index].data() as Map<String, dynamic>;
              final uid = users[index].id;
              final email = data['email'] ?? 'No email';

              return Card(
                margin: const EdgeInsets.all(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(email, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      if (data['idImageBase64'] != null) ...[
                        const Text("Government ID"),
                        const SizedBox(height: 6),
                        Image.memory(base64Decode(data['idImageBase64']), height: 160, fit: BoxFit.contain),
                        const SizedBox(height: 8),
                      ],
                      if (data['selfieBase64'] != null) ...[
                        const Text("Selfie"),
                        const SizedBox(height: 6),
                        Image.memory(base64Decode(data['selfieBase64']), height: 140, fit: BoxFit.contain),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                await FirebaseFirestore.instance.collection('users').doc(uid).update({
                                  'govIdVerified': true,
                                  'verificationRequested': false,
                                });
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("User approved")));
                              },
                              child: const Text("Approve"),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                await FirebaseFirestore.instance.collection('users').doc(uid).update({
                                  'verificationRequested': false,
                                  'govIdVerified': false,
                                });
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("User rejected")));
                              },
                              child: const Text("Reject"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------- AUTH GATE (real-time role) ----------------
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        final user = authSnap.data;
        if (user == null) return const HomePage(showAuthButtons: true);

        // Listen to user's doc in real-time (role)
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, roleSnap) {
            if (!roleSnap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));

            if (!roleSnap.data!.exists) return const HomePage(showAuthButtons: false);

            final data = roleSnap.data!.data() as Map<String, dynamic>;
            final role = data['role'] ?? 'user';

            if (role == 'admin') {
              return const AdminVerificationPage();
            } else {
              // If signed up with email/password and not verified, show verify page
              if (user.providerData.any((p) => p.providerId == 'password') && !user.emailVerified) {
                return const VerifyEmailPage();
              }
              return const HomePage(showAuthButtons: false);
            }
          },
        );
      },
    );
  }
}

// ---------------- HOME PAGE ----------------
class HomePage extends StatelessWidget {
  final bool showAuthButtons;
  const HomePage({super.key, required this.showAuthButtons});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("WorkConnect"),
        actions: [
          if (showAuthButtons) ...[
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage())),
              child: const Text("Register", style: TextStyle(color: Colors.black)),
            ),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage())),
              child: const Text("Login", style: TextStyle(color: Colors.black)),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage())),
                child: CircleAvatar(
                  radius: 18,
                  backgroundImage: user?.photoURL != null
                      ? NetworkImage(user!.photoURL!)
                      : const AssetImage('assets/anonymous.png') as ImageProvider,
                ),
              ),
            ),
          ]
        ],
      ),
      body: const HomeScreen(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: (_) {},
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.work), label: "Jobs"),
          BottomNavigationBarItem(icon: Icon(Icons.message), label: "Messages"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }
}

// ---------------- GOOGLE SIGN-IN (also ensures Firestore doc exists) ----------------
Future<void> signInWithGoogle(BuildContext context) async {
  try {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return;
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
    final user = userCred.user;
    if (user != null) {
      // ensure Firestore user doc exists (merge true to avoid overwriting)
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'email': user.email,
        'role': 'user',
        'govIdVerified': false,
        'verificationRequested': false,
      }, SetOptions(merge: true));
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Google Sign-In failed: $e")));
  }
}

// ---------------- REGISTER ----------------
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  String email = "", password = "", confirmPassword = "", phoneNumber = "";

  Future<void> register() async {
    if (!_formKey.currentState!.validate()) return;
    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Passwords do not match")));
      return;
    }
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);

      // Save user info in Firestore
      await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
        'email': email,
        'phone': phoneNumber,
        'role': 'user',
        'govIdVerified': false,
        'verificationRequested': false,
      });

      // Send verification email
      await cred.user?.sendEmailVerification();

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Verification email sent!")));
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? "Registration failed")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Register"), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context))),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(decoration: const InputDecoration(labelText: "Email"), keyboardType: TextInputType.emailAddress, validator: (v) => v!.contains("@") ? null : "Enter a valid email", onChanged: (v) => email = v),
              TextFormField(decoration: const InputDecoration(labelText: "Phone Number"), keyboardType: TextInputType.phone, validator: (v) => v!.isEmpty ? "Enter your phone number" : null, onChanged: (v) => phoneNumber = v),
              TextFormField(decoration: const InputDecoration(labelText: "Password"), obscureText: true, validator: (v) => v!.length >= 6 ? null : "Minimum 6 characters", onChanged: (v) => password = v),
              TextFormField(decoration: const InputDecoration(labelText: "Confirm Password"), obscureText: true, validator: (v) => v!.length >= 6 ? null : "Minimum 6 characters", onChanged: (v) => confirmPassword = v),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: register, child: const Text("Register")),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- LOGIN ----------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final formKey = GlobalKey<FormState>();
  String email = "", password = "";
  bool loading = false;

  Future<void> login() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? "Error")));
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login"), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context))),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: formKey,
          child: Column(
            children: [
              TextFormField(decoration: const InputDecoration(labelText: "Email"), onChanged: (v) => email = v, validator: (v) => v!.contains("@") ? null : "Enter valid email"),
              TextFormField(decoration: const InputDecoration(labelText: "Password"), obscureText: true, onChanged: (v) => password = v, validator: (v) => v!.length >= 6 ? null : "Minimum 6 characters"),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: loading ? null : login, child: loading ? const CircularProgressIndicator() : const Text("Login")),
              const SizedBox(height: 10),
              ElevatedButton.icon(icon: const Icon(Icons.login), label: const Text("Login with Google"), onPressed: () => signInWithGoogle(context)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- VERIFY EMAIL ----------------
class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key});
  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await FirebaseAuth.instance.currentUser?.reload();
      if (FirebaseAuth.instance.currentUser?.emailVerified ?? false) {
        timer?.cancel();
        if (mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage(showAuthButtons: false)));
        }
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Verify Email")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Please verify your email to continue."),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await FirebaseAuth.instance.currentUser?.sendEmailVerification();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Verification email resent!")));
              },
              child: const Text("Resend Verification Email"),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Worker Registration Page--------------
class WorkerRegistrationPage extends StatelessWidget {
  const WorkerRegistrationPage({super.key});
  @override
  Widget build(BuildContext context) {
    final _formKey = GlobalKey<FormState>();
    String name = "", address = "", phone = "", email = "";

    return Scaffold(
      appBar: AppBar(title: const Text("Worker Registration"), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(decoration: const InputDecoration(labelText: "Full Name"), onChanged: (v) => name = v, validator: (v) => v!.isEmpty ? "Enter your name" : null),
              TextFormField(decoration: const InputDecoration(labelText: "Address"), onChanged: (v) => address = v, validator: (v) => v!.isEmpty ? "Enter address" : null),
              TextFormField(decoration: const InputDecoration(labelText: "Phone Number"), keyboardType: TextInputType.phone, onChanged: (v) => phone = v, validator: (v) => v!.isEmpty ? "Enter phone number" : null),
              TextFormField(decoration: const InputDecoration(labelText: "Email"), keyboardType: TextInputType.emailAddress, onChanged: (v) => email = v, validator: (v) => v!.isEmpty || !v.contains("@") ? "Enter valid email" : null),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: () {
                if (_formKey.currentState!.validate()) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Worker Registered!")));
                  Navigator.pop(context);
                }
              }, child: const Text("Submit")),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Job Registration Page-------------
class JobRegistrationPage extends StatelessWidget {
  const JobRegistrationPage({super.key});
  @override
  Widget build(BuildContext context) {
    final _formKey = GlobalKey<FormState>();
    String name = "", address = "", phone = "", email = "";

    return Scaffold(
      appBar: AppBar(title: const Text("Job Registration"), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(decoration: const InputDecoration(labelText: "Full Name"), onChanged: (v) => name = v, validator: (v) => v!.isEmpty ? "Enter your name" : null),
              TextFormField(decoration: const InputDecoration(labelText: "Address"), onChanged: (v) => address = v, validator: (v) => v!.isEmpty ? "Enter address" : null),
              TextFormField(decoration: const InputDecoration(labelText: "Phone Number"), keyboardType: TextInputType.phone, onChanged: (v) => phone = v, validator: (v) => v!.isEmpty ? "Enter phone number" : null),
              TextFormField(decoration: const InputDecoration(labelText: "Email"), keyboardType: TextInputType.emailAddress, onChanged: (v) => email = v, validator: (v) => v!.isEmpty || !v.contains("@") ? "Enter valid email" : null),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: () {
                if (_formKey.currentState!.validate()) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Job Registered!")));
                  Navigator.pop(context);
                }
              }, child: const Text("Submit")),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- WORKER MODEL ----------------
class Worker {
  final String name;
  final String role;
  final double rating;
  final int reviews;
  final String skills;
  final String experience;
  final String rate;
  final String location;
  final String avatar;

  Worker({
    required this.name,
    required this.role,
    required this.rating,
    required this.reviews,
    required this.skills,
    required this.experience,
    required this.rate,
    required this.location,
    required this.avatar,
  });
}

final List<Worker> sampleWorkers = [
  Worker(name: "John Smith", role: "Plumber", rating: 4.7, reviews: 42, skills: "Pipe fitting, Leak repair, Water heater installation", experience: "8 years", rate: "\$60/hour", location: "New York, NY", avatar: "https://randomuser.me/api/portraits/men/32.jpg"),
  Worker(name: "Maria Garcia", role: "Electrician", rating: 4.9, reviews: 68, skills: "Wiring, Lighting installation, Circuit repair", experience: "12 years", rate: "\$75/hour", location: "Los Angeles, CA", avatar: "https://randomuser.me/api/portraits/women/44.jpg"),
];


// ---------------- Profile Page ---------------
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool isVerified = false;
  bool uploading = false;

  @override
  void initState() {
    super.initState();
    _checkVerificationStatus();
  }

  Future<void> _checkVerificationStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (doc.exists && doc.data()?['govIdVerified'] == true) {
      setState(() {
        isVerified = true;
      });
    }
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
    await GoogleSignIn().signOut();
    Navigator.pop(context);
  }

  Future<void> updateProfilePicture() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return;
    setState(() => uploading = true);
    try {
      final bytes = await File(picked.path).readAsBytes();
      final base64Str = base64Encode(bytes);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({'photoBase64': base64Str}, SetOptions(merge: true));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile picture updated")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed: $e")));
    } finally {
      setState(() => uploading = false);
    }
  }

  Future<void> verifyGovernmentID(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final picker = ImagePicker();

    // Pick Government ID (Gallery)
    final idImage = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (idImage == null) return;

    // Pick Selfie (Camera or gallery)
    final selfieImage = await picker.pickImage(source: ImageSource.camera, imageQuality: 50);
    if (selfieImage == null) return;

    setState(() => uploading = true);
    try {
      final idBytes = await File(idImage.path).readAsBytes();
      final selfieBytes = await File(selfieImage.path).readAsBytes();

      final idBase64 = base64Encode(idBytes);
      final selfieBase64 = base64Encode(selfieBytes);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'govIdVerified': false,
        'verificationRequested': true,
        'idImageBase64': idBase64,
        'selfieBase64': selfieBase64,
      }, SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ID & Selfie saved in Firestore! Waiting for admin review.")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload failed: $e")));
    } finally {
      setState(() => uploading = false);
    }
  }

  Widget base64ToImage(String base64String, {double width = 100, double height = 100}) {
    try {
      final decoded = base64Decode(base64String);
      return Image.memory(decoded, width: width, height: height, fit: BoxFit.cover);
    } catch (e) {
      return const Icon(Icons.broken_image, size: 50, color: Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text("Not logged in")));

    return Scaffold(
      appBar: AppBar(title: const Text("Profile"), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context))),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: StreamBuilder<DocumentSnapshot>(
          stream: getUserStream(user.uid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text("No profile data found"));

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final idImageBase64 = data['idImageBase64'] ?? '';
            final selfieBase64 = data['selfieBase64'] ?? '';
            final verified = data['govIdVerified'] ?? false;
            final photoBase64 = data['photoBase64'] ?? '';

            ImageProvider avatarImage;
            if (user.photoURL != null && user.photoURL!.isNotEmpty) {
              avatarImage = NetworkImage(user.photoURL!);
            } else if (photoBase64.isNotEmpty) {
              avatarImage = MemoryImage(base64Decode(photoBase64));
            } else {
              avatarImage = const AssetImage('assets/anonymous.png') as ImageProvider;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(radius: 40, backgroundImage: avatarImage),
                const SizedBox(height: 10),
                Text(user.email ?? "No email"),
                const SizedBox(height: 20),
                ElevatedButton(onPressed: updateProfilePicture, child: uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("Update Profile Picture")),
                const SizedBox(height: 20),
                ElevatedButton(onPressed: () => verifyGovernmentID(context), child: Text(verified ? "ID Verified ✅" : "Verify Government ID")),
                const SizedBox(height: 20),
                if (idImageBase64.isNotEmpty) ...[
                  const Text("Uploaded Government ID:"),
                  const SizedBox(height: 8),
                  base64ToImage(idImageBase64, width: 200, height: 120),
                  const SizedBox(height: 12),
                ],
                if (selfieBase64.isNotEmpty) ...[
                  const Text("Uploaded Selfie:"),
                  const SizedBox(height: 8),
                  base64ToImage(selfieBase64, width: 120, height: 120),
                ],
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  icon: const Icon(Icons.logout),
                  onPressed: logout,
                  label: const Text("Logout"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------- HOME SCREEN CONTENT ----------------
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Widget buildWorkerCard(Worker worker) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(backgroundImage: NetworkImage(worker.avatar), radius: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(worker.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text(worker.role, style: const TextStyle(color: Colors.blue)),
              Row(children: [const Icon(Icons.star, color: Colors.amber, size: 16), Text("${worker.rating} (${worker.reviews})")]),
            ]))
          ]),
          const SizedBox(height: 8),
          Text(worker.skills),
          const SizedBox(height: 4),
          Text(worker.experience),
          const SizedBox(height: 4),
          Text(worker.rate, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const Text("Find the right professional", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Text("for your home needs", style: TextStyle(fontSize: 22, color: Colors.blue)),
            const SizedBox(height: 12),
            const Text("Connect with skilled workers or find quality jobs in your area.", textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              ElevatedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkerRegistrationPage())), child: const Text("Find a Worker")),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JobRegistrationPage())), child: const Text("Find a Job")),
            ])
          ]),
        ),
      ),
      const SizedBox(height: 20),
      const Text("Top Rated Workers", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      ...sampleWorkers.map(buildWorkerCard).toList(),
    ]);
  }
}
