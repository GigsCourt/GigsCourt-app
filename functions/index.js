const functions = require("firebase-functions");
const ImageKit = require("imagekit");

const imagekit = new ImageKit({
  publicKey: "public_YDOcWLpiiHDlpU+y4GXqUjVDEaQ=",
  privateKey: "private_g6D6+rm4r4+Rh1PqoEDuD+zSmjI=",
  urlEndpoint: "https://ik.imagekit.io/GigsKourt"
});

exports.getImageKitToken = functions.https.onCall((data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'You must be logged in to upload images.'
    );
  }

  const authenticationParameters = imagekit.getAuthenticationParameters();
  return authenticationParameters;
});