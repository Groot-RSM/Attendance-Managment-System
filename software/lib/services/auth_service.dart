import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Auth State Stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Get Current User
  User? get currentUser => _auth.currentUser;

  // Email/Password Sign Up
  Future<UserCredential?> registerWithEmail(String email, String password, String name, String phone) async {
    try {
      final UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Save additional user info to Firestore
      if (userCredential.user != null) {
        String role = email.toLowerCase() == 'manneysatheesh@gmail.com' ? 'admin' : 'teacher';
        
        await _db.collection('users').doc(userCredential.user!.uid).set({
          'name': name,
          'phone': phone,
          'email': email,
          'role': role,
          'classId': role == 'admin' ? 'ALL' : null, // Teachers start unassigned
          'section': role == 'admin' ? 'ALL' : null,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      print('FirebaseAuth error during registration: ${e.message}');
      rethrow;
    } catch (e) {
      print('Error registering with email: $e');
      rethrow;
    }
  }

  // Email/Password Login
  Future<UserCredential?> loginWithEmail(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      // Auto-create the admin account on first login if it doesn't exist!
      if (email.toLowerCase() == 'manneysatheesh@gmail.com') {
        try {
          return await registerWithEmail(email, password, 'Admin', '');
        } on FirebaseAuthException catch (regError) {
          if (regError.code == 'email-already-in-use') {
             // Account exists, they just typed the wrong password. Throw original error.
             print('Admin wrong password: ${e.message}');
             rethrow;
          }
        }
      }
      print('FirebaseAuth error during login: ${e.message}');
      rethrow;
    } catch (e) {
      print('Error logging in with email: $e');
      rethrow;
    }
  }

  // Update password for current user
  Future<void> updatePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user != null) {
      await user.updatePassword(newPassword);
    }
  }

  // Google Sign In
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return null; // The user canceled the sign-in
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create a new credential
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Once signed in, return the UserCredential
      final UserCredential userCredential = await _auth.signInWithCredential(credential);

      // Check if user exists in Firestore (by email or UID)
      if (userCredential.user != null) {
        bool isAuthorized = false;
        
        // 1. Check if they were whitelisted by their email
        if (userCredential.user!.email != null) {
          final emailDoc = await _db.collection('users').doc(userCredential.user!.email!.toLowerCase()).get();
          if (emailDoc.exists) {
            isAuthorized = true;
          }
        }
        
        // 2. Check if they have a legacy UID-based document
        if (!isAuthorized) {
          final uidDoc = await _db.collection('users').doc(userCredential.user!.uid).get();
          if (uidDoc.exists) {
            isAuthorized = true;
          }
        }

        if (!isAuthorized) {
          // They haven't been whitelisted by the Admin!
          await userCredential.user!.delete();
          await signOut();
          throw Exception('Your email is not registered by the Admin.');
        }
      }

      return userCredential;
    } catch (e) {
      print('Error signing in with Google: $e');
      rethrow;
    }
  }

  // Sign Out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
