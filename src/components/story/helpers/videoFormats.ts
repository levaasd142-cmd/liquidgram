export const PRIMARY_VIDEO_MIME = 'video/mp4; codecs=hvc1.1.6.L63.00';
export const SECONDARY_VIDEO_MIME = 'video/mp4; codecs=avc1.64001E';
// Stories have an alternative video for browsers that cannot play the primary one
export const CAN_PLAY_PRIMARY_VIDEO = Boolean(document.createElement('video').canPlayType(PRIMARY_VIDEO_MIME));
