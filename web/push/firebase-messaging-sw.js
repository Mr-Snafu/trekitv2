importScripts('https://www.gstatic.com/firebasejs/9.10.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.10.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAFdsQRjiX17sIjQZmBHK8aZd8MDzLbzq8',
  appId: '1:692333975435:web:fe0a7d803d6039b89b818e',
  messagingSenderId: '692333975435',
  projectId: 'trekit-10e88',
  authDomain: 'trekit-10e88.firebaseapp.com',
  storageBucket: 'trekit-10e88.firebasestorage.app',
});

firebase.messaging();
