# iosFaceDetectorTracker

Simple exercise of testing Face Detector and Tracking using Vision Framework on iOS.
It supports just single face.

Face Detector in Vision Framework seems to normalize an input image to its internal canonical size to make a predefiend levels of image pyramid. 
In my case, I just want to detect a big face, thus the coarest levels of the pyramid would be enough, but the API does not support it. I hope the next version of API to support specifying minimum and maximum face size.

Face Detector on iPhone 6S was not fast enough for the real-time application (15-18 fps), thus I detect the face every 15 frames and track the previously detected bounding box for other 14 frames.
