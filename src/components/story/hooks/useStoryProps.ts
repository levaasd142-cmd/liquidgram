import type { ApiTypeStory } from '../../../api/types';
import { ApiMediaFormat } from '../../../api/types';

import { getStoryMediaHash, hasMessageText } from '../../../global/helpers';
import { IS_PROGRESSIVE_SUPPORTED } from '../../../util/browser/windowEnvironment';
import { getProgressiveUrl } from '../../../util/mediaLoader';
import { CAN_PLAY_PRIMARY_VIDEO, PRIMARY_VIDEO_MIME } from '../helpers/videoFormats';

import useMedia from '../../../hooks/useMedia';
import { checkIfStreamingSupported } from '../../../hooks/useStreaming';

// Without a service worker, as in the iOS app, a progressive video downloads in full. Safari still streams the
// primary video through Managed Media Source straight from the API, and a download of the alternative video is
// needed only where the primary one does not play.
const SHOULD_STREAM_WITHOUT_SERVICE_WORKER = !IS_PROGRESSIVE_SUPPORTED
  && checkIfStreamingSupported(PRIMARY_VIDEO_MIME);

export default function useStoryProps(
  story?: ApiTypeStory, isCurrentUserPremium = false, isDropdownMenuOpen = false,
) {
  const isLoadedStory = story && 'content' in story;
  const isDeletedStory = story && 'isDeleted' in story;
  const hasText = isLoadedStory ? hasMessageText(story) : false;
  const hasForwardInfo = isLoadedStory && Boolean(story.forwardInfo);

  let thumbnail: string | undefined;
  if (isLoadedStory) {
    if (story.content.photo?.thumbnail) {
      thumbnail = story.content.photo.thumbnail.dataUri;
    }
    if (story.content.video?.thumbnail?.dataUri) {
      thumbnail = story.content.video.thumbnail.dataUri;
    }
  }

  const previewHash = isLoadedStory ? getStoryMediaHash(story) : undefined;
  const previewBlobUrl = useMedia(previewHash);
  const isVideo = Boolean(isLoadedStory && story.content.video);
  const noSound = isLoadedStory && story.content.video?.noSound;
  const fullMediaHash = isLoadedStory ? getStoryMediaHash(story, 'full') : undefined;
  const shouldStreamVideo = isVideo && SHOULD_STREAM_WITHOUT_SERVICE_WORKER;
  const downloadedMediaData = useMedia(
    fullMediaHash, !story || shouldStreamVideo, isVideo ? ApiMediaFormat.Progressive : ApiMediaFormat.BlobUrl,
  );
  const fullMediaData = shouldStreamVideo && fullMediaHash ? getProgressiveUrl(fullMediaHash) : downloadedMediaData;
  const isAltVideoNeeded = IS_PROGRESSIVE_SUPPORTED || (!shouldStreamVideo && !CAN_PLAY_PRIMARY_VIDEO);
  const altMediaHash = isVideo && isLoadedStory && isAltVideoNeeded
    ? getStoryMediaHash(story, 'full', true)
    : undefined;
  const altMediaData = useMedia(altMediaHash, !story, ApiMediaFormat.Progressive);

  const hasFullData = Boolean(fullMediaData || altMediaData);
  const bestImageData = isVideo ? previewBlobUrl : fullMediaData || previewBlobUrl;
  const hasThumb = !previewBlobUrl && !hasFullData;

  const canDownload = isCurrentUserPremium && isLoadedStory && !story.noForwards;
  const downloadHash = isLoadedStory ? getStoryMediaHash(story, 'download') : undefined;
  const downloadMediaData = useMedia(downloadHash, !canDownload && !isDropdownMenuOpen);

  return {
    isLoadedStory,
    isDeletedStory,
    hasText,
    hasForwardInfo,
    thumbnail,
    previewHash,
    previewBlobUrl,
    isVideo,
    noSound,
    fullMediaHash,
    fullMediaData,
    altMediaHash,
    altMediaData,
    hasFullData,
    bestImageData,
    hasThumb,
    canDownload,
    downloadMediaData,
  };
}
