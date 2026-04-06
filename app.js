const STORAGE_KEY = "pulseplay-demo-v1";
const currentUserId = "user-1";

const seedData = {
  users: [
    {
      id: "user-1",
      handle: "sammy",
      displayName: "Sammy Rivers",
      bio: "Builder, editor, and all-night idea collector.",
      interests: ["music", "travel", "food", "education"],
      following: ["user-2", "user-3"],
      followers: ["user-2", "user-4"],
    },
    {
      id: "user-2",
      handle: "lunaloops",
      displayName: "Luna Loops",
      bio: "High-energy edits, beat cuts, and color-heavy city reels.",
      interests: ["music", "fashion", "travel"],
      following: ["user-1"],
      followers: ["user-1", "user-3", "user-4"],
    },
    {
      id: "user-3",
      handle: "platepassport",
      displayName: "Plate Passport",
      bio: "Street food diaries and quick restaurant storytelling.",
      interests: ["food", "travel", "comedy"],
      following: ["user-1", "user-2"],
      followers: ["user-1", "user-4"],
    },
    {
      id: "user-4",
      handle: "coachnova",
      displayName: "Coach Nova",
      bio: "Fitness routines, mindset, and realistic daily training.",
      interests: ["fitness", "education", "music"],
      following: ["user-2"],
      followers: ["user-3"],
    },
  ],
  posts: [
    {
      id: "post-1",
      userId: "user-2",
      title: "Neon tram at 2AM",
      caption: "Fast-cut city textures, slowed just enough to catch the glow.",
      videoUrl: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4",
      category: "travel",
      tags: ["city", "neon", "music", "travel"],
      createdAt: Date.now() - 1000 * 60 * 90,
      likes: ["user-1", "user-3"],
      comments: [
        { id: "comment-1", userId: "user-1", text: "The pacing on this is so good." },
      ],
      edit: { trimStart: 1, trimEnd: 17, playbackRate: 1.25, filter: "cinematic" },
      views: 1820,
    },
    {
      id: "post-2",
      userId: "user-3",
      title: "Five-dollar noodle stop",
      caption: "A tiny place with huge flavor and a line out the door.",
      videoUrl: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
      category: "food",
      tags: ["food", "budget", "travel", "street"],
      createdAt: Date.now() - 1000 * 60 * 60 * 5,
      likes: ["user-2", "user-4"],
      comments: [
        { id: "comment-2", userId: "user-4", text: "Adding this to my trip list." },
        { id: "comment-3", userId: "user-1", text: "The broth shot sold me instantly." },
      ],
      edit: { trimStart: 4, trimEnd: 22, playbackRate: 1, filter: "warm" },
      views: 960,
    },
    {
      id: "post-3",
      userId: "user-4",
      title: "12-minute cardio ladder",
      caption: "Low equipment, full-body, and built for consistency over intensity.",
      videoUrl: "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4",
      category: "fitness",
      tags: ["fitness", "routine", "education", "health"],
      createdAt: Date.now() - 1000 * 60 * 60 * 20,
      likes: ["user-3"],
      comments: [],
      edit: { trimStart: 0, trimEnd: 12, playbackRate: 1, filter: "vivid" },
      views: 1220,
    },
  ],
  messages: [
    {
      id: "thread-1",
      users: ["user-1", "user-2"],
      messages: [
        { id: "msg-1", senderId: "user-2", text: "If you launch this, I want creator early access.", sentAt: Date.now() - 1000 * 60 * 50 },
        { id: "msg-2", senderId: "user-1", text: "Deal. I’m tuning the feed so music edits get a real chance.", sentAt: Date.now() - 1000 * 60 * 43 },
      ],
    },
    {
      id: "thread-2",
      users: ["user-1", "user-3"],
      messages: [
        { id: "msg-3", senderId: "user-3", text: "Could use a collab feature later, but this already feels sharp.", sentAt: Date.now() - 1000 * 60 * 130 },
      ],
    },
  ],
  interactions: {
    watchedCategories: {
      travel: 5,
      food: 3,
      education: 2,
      fitness: 1,
    },
  },
};

let state = loadState();
let activeFeed = "for-you";
let activeView = "feed";
let focusedPostId = state.posts[0]?.id ?? null;
let previewObjectUrl = "";

const filterMap = {
  none: "none",
  cinematic: "contrast(1.08) saturate(0.88) sepia(0.18) brightness(0.92)",
  vivid: "saturate(1.4) contrast(1.05)",
  mono: "grayscale(1) contrast(1.1)",
  warm: "sepia(0.28) saturate(1.15) brightness(1.02)",
};

const profileCard = document.querySelector("#profileCard");
const algorithmCard = document.querySelector("#algorithmCard");
const feedList = document.querySelector("#feedList");
const creatorList = document.querySelector("#creatorList");
const commentFocus = document.querySelector("#commentFocus");
const feedTitle = document.querySelector("#feedTitle");
const uploadForm = document.querySelector("#uploadForm");
const editorPreview = document.querySelector("#editorPreview");
const previewStats = document.querySelector("#previewStats");
const messageThreads = document.querySelector("#messageThreads");
const messageForm = document.querySelector("#messageForm");
const messageRecipient = document.querySelector("#messageRecipient");
const navButtons = document.querySelectorAll(".nav-card");
const feedButtons = document.querySelectorAll(".toggle");

bootstrap();

function bootstrap() {
  bindGlobalEvents();
  renderAll();
}

function loadState() {
  const saved = localStorage.getItem(STORAGE_KEY);
  if (!saved) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(seedData));
    return structuredClone(seedData);
  }

  try {
    return JSON.parse(saved);
  } catch (error) {
    console.warn("Resetting invalid local state", error);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(seedData));
    return structuredClone(seedData);
  }
}

function saveState() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

function bindGlobalEvents() {
  uploadForm.addEventListener("submit", handleUpload);
  uploadForm.videoFile.addEventListener("change", handlePreviewSource);
  uploadForm.videoUrl.addEventListener("input", handlePreviewSource);
  uploadForm.trimStart.addEventListener("input", renderPreviewMeta);
  uploadForm.trimEnd.addEventListener("input", renderPreviewMeta);
  uploadForm.playbackRate.addEventListener("input", renderPreviewMeta);
  uploadForm.filter.addEventListener("change", renderPreviewMeta);
  editorPreview.addEventListener("timeupdate", loopTrimmedVideo);

  messageForm.addEventListener("submit", handleSendMessage);

  navButtons.forEach((button) => {
    button.addEventListener("click", () => {
      activeView = button.dataset.view;
      navButtons.forEach((item) => item.classList.toggle("is-active", item === button));
      if (activeView === "following") {
        activeFeed = "following";
      }
      if (activeView === "feed") {
        activeFeed = "for-you";
      }
      syncFeedButtons();
      scrollSectionIntoView();
      renderAll();
    });
  });

  feedButtons.forEach((button) => {
    button.addEventListener("click", () => {
      activeFeed = button.dataset.feed;
      activeView = activeFeed === "following" ? "following" : "feed";
      syncFeedButtons();
      renderFeed();
    });
  });
}

function scrollSectionIntoView() {
  if (activeView === "upload") {
    document.querySelector("#uploadView").scrollIntoView({ behavior: "smooth", block: "start" });
  } else if (activeView === "messages") {
    document.querySelector("#messagesView").scrollIntoView({ behavior: "smooth", block: "start" });
  } else {
    document.querySelector("#feedList").scrollIntoView({ behavior: "smooth", block: "start" });
  }
}

function syncFeedButtons() {
  feedButtons.forEach((button) => {
    button.classList.toggle("is-active", button.dataset.feed === activeFeed);
  });
}

function renderAll() {
  renderProfileCard();
  renderAlgorithmCard();
  renderFeed();
  renderCreators();
  renderCommentFocus();
  renderMessages();
  renderPreviewMeta();
}

function renderProfileCard() {
  const user = getCurrentUser();
  profileCard.innerHTML = `
    <p class="eyebrow">Your profile</p>
    <h3>${user.displayName}</h3>
    <p class="lede">@${user.handle}</p>
    <p class="section-copy">${user.bio}</p>
    <div class="metrics">
      <div class="metric">
        <strong>${getFollowerCount(user.id)}</strong>
        <span class="metric-label">Followers</span>
      </div>
      <div class="metric">
        <strong>${user.following.length}</strong>
        <span class="metric-label">Following</span>
      </div>
      <div class="metric">
        <strong>${state.posts.filter((post) => post.userId === user.id).length}</strong>
        <span class="metric-label">Videos</span>
      </div>
    </div>
  `;
}

function renderAlgorithmCard() {
  const user = getCurrentUser();
  const watched = Object.entries(state.interactions.watchedCategories)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 4);
  const topSignals = [...new Set([...user.interests, ...watched.map(([category]) => category)])].slice(0, 5);
  algorithmCard.innerHTML = `
    <p class="eyebrow">Algorithm signals</p>
    <h3>Your feed learns from follows, likes, comments, watch categories, and recency.</h3>
    <div class="preview-stats">
      ${topSignals.map((signal) => `<span class="algorithm-pill">${signal}</span>`).join("")}
    </div>
  `;
}

function renderFeed() {
  const posts = getRankedPosts(activeFeed);
  feedTitle.textContent = activeFeed === "following" ? "From people you follow" : "Recommended for you";
  feedList.innerHTML = "";

  posts.forEach(({ post, score }) => {
    const template = document.querySelector("#feedCardTemplate");
    const node = template.content.firstElementChild.cloneNode(true);
    const author = getUser(post.userId);
    const liked = post.likes.includes(currentUserId);
    const following = getCurrentUser().following.includes(author.id);

    node.querySelector(".creator-line").textContent = `@${author.handle} • ${formatTimeAgo(post.createdAt)} • ${post.views} views`;
    node.querySelector("h4").textContent = post.title;
    node.querySelector(".caption").textContent = post.caption;
    node.querySelector(".score-chip").textContent = `${Math.round(score)} match`;

    const video = node.querySelector("video");
    video.src = post.videoUrl;
    applyEditProfile(video, post.edit);
    video.addEventListener("play", () => trackView(post));
    video.addEventListener("timeupdate", () => loopPostVideo(video, post.edit));

    const tagRow = node.querySelector(".tag-row");
    tagRow.innerHTML = post.tags.map((tag) => `<span class="tag">#${tag}</span>`).join("");

    const likeButton = node.querySelector(".like-button");
    likeButton.textContent = liked ? `Liked • ${post.likes.length}` : `Like • ${post.likes.length}`;
    likeButton.addEventListener("click", () => toggleLike(post.id));

    const commentButton = node.querySelector(".comment-button");
    commentButton.textContent = `Comments • ${post.comments.length}`;
    commentButton.addEventListener("click", () => {
      focusedPostId = post.id;
      renderCommentFocus();
      commentFocus.scrollIntoView({ behavior: "smooth", block: "nearest" });
    });

    const followButton = node.querySelector(".follow-button");
    followButton.textContent = following ? "Following" : "Follow";
    followButton.addEventListener("click", () => toggleFollow(author.id));

    node.querySelector(".message-button").addEventListener("click", () => openMessageThread(author.id));

    const commentForm = node.querySelector(".comment-form");
    commentForm.addEventListener("submit", (event) => {
      event.preventDefault();
      const comment = new FormData(commentForm).get("comment").toString().trim();
      if (!comment) return;
      addComment(post.id, comment);
      commentForm.reset();
    });

    const commentList = node.querySelector(".comment-list");
    commentList.innerHTML = post.comments.slice(0, 3).map((comment) => {
      const commenter = getUser(comment.userId);
      return `
        <div class="comment-item">
          <strong>@${commenter.handle}</strong>
          <p class="comment">${comment.text}</p>
        </div>
      `;
    }).join("");

    feedList.appendChild(node);
  });
}

function renderCreators() {
  const currentUser = getCurrentUser();
  const candidates = state.users
    .filter((user) => user.id !== currentUser.id)
    .sort((a, b) => getCreatorSuggestionScore(b) - getCreatorSuggestionScore(a));

  creatorList.innerHTML = "";
  candidates.forEach((user) => {
    const sharedInterests = user.interests.filter((interest) => currentUser.interests.includes(interest)).length;
    const following = currentUser.following.includes(user.id);
    const item = document.createElement("article");
    item.className = "creator-item";
    item.innerHTML = `
      <header>
        <div>
          <strong>${user.displayName}</strong>
          <p class="creator-line">@${user.handle}</p>
        </div>
        <span class="creator-stats">${getFollowerCount(user.id)} followers</span>
      </header>
      <p class="section-copy">${user.bio}</p>
      <p class="creator-stats">${sharedInterests} shared interests</p>
    `;

    const controls = document.createElement("div");
    controls.className = "toggle-row";

    const followButton = document.createElement("button");
    followButton.className = "secondary-button";
    followButton.textContent = following ? "Following" : "Follow";
    followButton.addEventListener("click", () => toggleFollow(user.id));

    const messageButton = document.createElement("button");
    messageButton.className = "secondary-button";
    messageButton.textContent = "Message";
    messageButton.addEventListener("click", () => openMessageThread(user.id));

    controls.append(followButton, messageButton);
    item.appendChild(controls);
    creatorList.appendChild(item);
  });

  messageRecipient.innerHTML = candidates.map((user) => `<option value="${user.id}">${user.displayName} (@${user.handle})</option>`).join("");
}

function renderCommentFocus() {
  const post = state.posts.find((item) => item.id === focusedPostId) ?? state.posts[0];
  if (!post) {
    commentFocus.innerHTML = "<p class='section-copy'>Comments will show up here.</p>";
    return;
  }
  const author = getUser(post.userId);
  commentFocus.innerHTML = `
    <article class="comment-item">
      <strong>${post.title}</strong>
      <p class="creator-line">by @${author.handle}</p>
    </article>
    ${post.comments.map((comment) => {
      const commenter = getUser(comment.userId);
      return `
        <article class="comment-item">
          <strong>@${commenter.handle}</strong>
          <p class="comment">${comment.text}</p>
        </article>
      `;
    }).join("") || "<p class='section-copy'>No comments yet. Be the first one.</p>"}
  `;
}

function renderMessages() {
  const threads = state.messages
    .filter((thread) => thread.users.includes(currentUserId))
    .sort((a, b) => getLatestMessageTime(b) - getLatestMessageTime(a));

  messageThreads.innerHTML = "";
  threads.forEach((thread) => {
    const otherUser = getUser(thread.users.find((id) => id !== currentUserId));
    const latest = thread.messages[thread.messages.length - 1];
    const item = document.createElement("article");
    item.className = "thread-item";
    item.innerHTML = `
      <header>
        <strong>${otherUser.displayName}</strong>
        <span class="creator-stats">@${otherUser.handle}</span>
      </header>
      <p class="section-copy">${latest.text}</p>
      <p class="creator-stats">${formatTimeAgo(latest.sentAt)}</p>
    `;
    messageThreads.appendChild(item);
  });
}

function handlePreviewSource() {
  const file = uploadForm.videoFile.files[0];
  const url = uploadForm.videoUrl.value.trim();

  if (previewObjectUrl) {
    URL.revokeObjectURL(previewObjectUrl);
    previewObjectUrl = "";
  }

  if (file) {
    previewObjectUrl = URL.createObjectURL(file);
    editorPreview.src = previewObjectUrl;
  } else if (url) {
    editorPreview.src = url;
  } else {
    editorPreview.removeAttribute("src");
    editorPreview.load();
  }
  renderPreviewMeta();
}

function renderPreviewMeta() {
  const edit = getEditorValues();
  editorPreview.playbackRate = edit.playbackRate;
  editorPreview.style.filter = filterMap[edit.filter];
  previewStats.innerHTML = `
    <span class="algorithm-pill">Trim ${edit.trimStart}s to ${edit.trimEnd}s</span>
    <span class="algorithm-pill">${edit.playbackRate}x speed</span>
    <span class="algorithm-pill">${edit.filter} filter</span>
  `;
}

function loopTrimmedVideo() {
  const { trimStart, trimEnd } = getEditorValues();
  if (editorPreview.currentTime >= trimEnd) {
    editorPreview.currentTime = trimStart;
  }
}

function handleUpload(event) {
  event.preventDefault();
  const formData = new FormData(uploadForm);
  const file = uploadForm.videoFile.files[0];
  const pastedUrl = formData.get("videoUrl").toString().trim();

  let videoUrl = pastedUrl;
  if (!videoUrl && file) {
    videoUrl = previewObjectUrl || URL.createObjectURL(file);
    previewObjectUrl = "";
  }

  if (!videoUrl) {
    alert("Add a local video file or paste a public video URL.");
    return;
  }

  const post = {
    id: crypto.randomUUID(),
    userId: currentUserId,
    title: formData.get("title").toString(),
    caption: formData.get("caption").toString(),
    videoUrl,
    category: formData.get("category").toString(),
    tags: formData.get("tags").toString().split(",").map((tag) => tag.trim().toLowerCase()).filter(Boolean),
    createdAt: Date.now(),
    likes: [],
    comments: [],
    edit: getEditorValues(),
    views: 0,
  };

  state.posts.unshift(post);
  focusedPostId = post.id;
  state.interactions.watchedCategories[post.category] = (state.interactions.watchedCategories[post.category] || 0) + 2;
  saveState();
  uploadForm.reset();
  editorPreview.removeAttribute("src");
  editorPreview.load();
  renderAll();
}

function handleSendMessage(event) {
  event.preventDefault();
  const formData = new FormData(messageForm);
  const recipientId = formData.get("recipient").toString();
  const text = formData.get("message").toString().trim();
  if (!recipientId || !text) return;

  let thread = state.messages.find((item) => item.users.includes(currentUserId) && item.users.includes(recipientId));
  if (!thread) {
    thread = {
      id: crypto.randomUUID(),
      users: [currentUserId, recipientId],
      messages: [],
    };
    state.messages.push(thread);
  }

  thread.messages.push({
    id: crypto.randomUUID(),
    senderId: currentUserId,
    text,
    sentAt: Date.now(),
  });

  saveState();
  messageForm.reset();
  renderMessages();
}

function getRankedPosts(feedType) {
  const currentUser = getCurrentUser();
  let posts = [...state.posts];

  if (feedType === "following") {
    posts = posts.filter((post) => currentUser.following.includes(post.userId) || post.userId === currentUserId);
  }

  return posts
    .map((post) => ({ post, score: calculatePostScore(post) }))
    .sort((a, b) => b.score - a.score);
}

function calculatePostScore(post) {
  const currentUser = getCurrentUser();
  const author = getUser(post.userId);
  const hoursOld = (Date.now() - post.createdAt) / (1000 * 60 * 60);
  const recencyScore = Math.max(8, 40 - hoursOld * 1.2);
  const interestScore = post.tags.reduce((total, tag) => total + (currentUser.interests.includes(tag) ? 12 : 0), 0);
  const categoryScore = (state.interactions.watchedCategories[post.category] || 0) * 6;
  const followingScore = currentUser.following.includes(author.id) ? 24 : 0;
  const engagementScore = post.likes.length * 3 + post.comments.length * 4 + Math.log10(post.views + 10) * 8;
  const selfBoost = post.userId === currentUserId ? 18 : 0;
  return recencyScore + interestScore + categoryScore + followingScore + engagementScore + selfBoost;
}

function getCreatorSuggestionScore(user) {
  const currentUser = getCurrentUser();
  const overlap = user.interests.filter((interest) => currentUser.interests.includes(interest)).length * 10;
  const followers = getFollowerCount(user.id) * 2;
  const alreadyFollowedPenalty = currentUser.following.includes(user.id) ? -30 : 0;
  return overlap + followers + alreadyFollowedPenalty;
}

function toggleLike(postId) {
  const post = state.posts.find((item) => item.id === postId);
  if (!post) return;
  const liked = post.likes.includes(currentUserId);
  post.likes = liked ? post.likes.filter((id) => id !== currentUserId) : [...post.likes, currentUserId];
  if (!liked) {
    state.interactions.watchedCategories[post.category] = (state.interactions.watchedCategories[post.category] || 0) + 1;
  }
  saveState();
  renderAll();
}

function addComment(postId, text) {
  const post = state.posts.find((item) => item.id === postId);
  if (!post) return;
  post.comments.unshift({
    id: crypto.randomUUID(),
    userId: currentUserId,
    text,
  });
  state.interactions.watchedCategories[post.category] = (state.interactions.watchedCategories[post.category] || 0) + 1;
  focusedPostId = postId;
  saveState();
  renderAll();
}

function toggleFollow(targetUserId) {
  if (targetUserId === currentUserId) return;
  const currentUser = getCurrentUser();
  const targetUser = getUser(targetUserId);
  const following = currentUser.following.includes(targetUserId);

  currentUser.following = following
    ? currentUser.following.filter((id) => id !== targetUserId)
    : [...currentUser.following, targetUserId];

  targetUser.followers = following
    ? targetUser.followers.filter((id) => id !== currentUserId)
    : [...new Set([...targetUser.followers, currentUserId])];

  saveState();
  renderAll();
}

function openMessageThread(userId) {
  messageRecipient.value = userId;
  activeView = "messages";
  navButtons.forEach((item) => item.classList.toggle("is-active", item.dataset.view === "messages"));
  document.querySelector("#messagesView").scrollIntoView({ behavior: "smooth", block: "start" });
}

function trackView(post) {
  post.views += 1;
  state.interactions.watchedCategories[post.category] = (state.interactions.watchedCategories[post.category] || 0) + 0.25;
  saveState();
}

function getEditorValues() {
  const trimStart = Number(uploadForm.trimStart.value);
  const trimEnd = Math.max(trimStart + 1, Number(uploadForm.trimEnd.value));
  const playbackRate = Number(uploadForm.playbackRate.value);
  const filter = uploadForm.filter.value;
  return { trimStart, trimEnd, playbackRate, filter };
}

function applyEditProfile(video, edit = {}) {
  video.playbackRate = edit.playbackRate || 1;
  video.style.filter = filterMap[edit.filter] || filterMap.none;
}

function loopPostVideo(video, edit = {}) {
  const trimStart = edit.trimStart ?? 0;
  const trimEnd = edit.trimEnd ?? Number.POSITIVE_INFINITY;
  if (video.currentTime >= trimEnd) {
    video.currentTime = trimStart;
  }
}

function getCurrentUser() {
  return getUser(currentUserId);
}

function getUser(userId) {
  return state.users.find((user) => user.id === userId);
}

function getFollowerCount(userId) {
  return state.users.reduce((total, user) => total + (user.following.includes(userId) ? 1 : 0), 0);
}

function getLatestMessageTime(thread) {
  return thread.messages[thread.messages.length - 1]?.sentAt ?? 0;
}

function formatTimeAgo(timestamp) {
  const seconds = Math.floor((Date.now() - timestamp) / 1000);
  const intervals = [
    ["d", 86400],
    ["h", 3600],
    ["m", 60],
  ];

  for (const [label, size] of intervals) {
    if (seconds >= size) {
      return `${Math.floor(seconds / size)}${label} ago`;
    }
  }
  return "just now";
}
