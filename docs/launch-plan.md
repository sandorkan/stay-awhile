# Stay awhile launch plan

Created: 2026-09-21

Goal: help Claude Code users discover Stay awhile, try it, and share feedback.
First milestone: 10 people who have used it and told us about their experience.

Work through the phases in order. Check off completed tasks and record links
and findings in the launch log below. This is a plan, not a record of completed
submissions or permission to publish posts.

## Positioning

Lead with the experience: a calmer way to stay with one task while Claude works.
Show the landscape and let people hear the music and completion cues. Describe
the intention without promising measurable productivity improvements.

Suggested short description:

> Ambient music and animated pixel-art landscapes for calmer Claude Code sessions.

Repository: https://github.com/sandorkan/stay-awhile

Keep donations optional and secondary. The existing README and viewer settings
links are enough for the initial launch.

## 1. Prepare a short demo

- [ ] Record a 20–30-second video with sound.
- [ ] Show Claude Code working beside the floating landscape.
- [ ] Capture subtle scene movement and ambient music, then a completion cue.
- [ ] Briefly show all four scenes through the settings menu.
- [ ] Add captions so the video also makes sense with sound muted.
- [ ] Check the recording for private terminal content, paths, and notifications.
- [ ] Export a short, lightweight GIF for the README and add it near the top.
- [ ] Keep the full video ready for launch posts.

Suggested sequence:

| Time | Content |
| --- | --- |
| 0–5 seconds | Claude working beside the floating scene; introduce Stay awhile. |
| 5–13 seconds | Landscape movement and music; caption explains the purpose. |
| 13–20 seconds | Switch through Lakeside, Alpine Valley, Coastal Lighthouse, and Desert Canyon. |
| 20–25 seconds | Turn completes and the completion cue plays. |
| 25–30 seconds | “Free and open source” with the repository address. |

Ready when: a new viewer can understand what it does without reading the README.

## 2. Make GitHub ready for visitors

- [x] Check the repository description against the suggested wording above.
- [x] Review and add relevant topics: `claude-code`, `claude-code-plugin`,
      `pixel-art`, `ambient-music`, and `developer-tools`.
- [x] Follow the README installation instructions (Sandro confirmed the installation test passed after reloading plugins).
- [x] Verify that opening the viewer and changing scene, music, and volume work.
- [x] Confirm platform requirements and known limitations are easy to find.
- [ ] Add the demo GIF and verify it displays on GitHub.
- [ ] Choose a release version consistent with the plugin manifest and publish
      a tagged release with a short feature summary and installation instructions.

Ready when: someone unfamiliar with the project can install it from the README
and reach the experience shown in the demo.

This phase can start before the demo is recorded. Only the GIF task depends
on phase 1. Release notes are prepared in [release-v0.1.0.md](release-v0.1.0.md);
installation and viewer checks have been confirmed by Sandro. Release publication
is the remaining step; the demo GIF is deferred until phase 1 is complete.

Checks on 2026-09-21: the README command names match the marketplace and command
files; 25 Python regression tests and the viewer runtime checks passed. These
do not establish that a fresh installation or real browser pop-out was tested.

Discovery reference: [GitHub's Claude Code plugin topic](https://github.com/topics/claude-code-plugin).

Installation feedback: Sandro reported that audio started only after running
`/reload-plugins` following installation. Added this step immediately after
installation in the README and release notes, and noted it in the audio guide.
Sandro subsequently confirmed that the remaining checks worked. This is a
user-reported pass on the tested setup, not a claim of testing every platform.

## 3. Submit to Anthropic's plugin directory

- [ ] Open the [official plugin directory](https://claude.com/plugins) and follow
      “Submit your plugin”.
- [ ] Review the current submission requirements.
- [ ] Prepare the repository URL, description, installation instructions, and demo.
- [ ] Submit the plugin and record the date and any confirmation link below.
- [ ] Record and address any review feedback.

The directory offered reviewed submissions when this plan was written.
Requirements can change, and acceptance is not guaranteed. Community outreach
can proceed while the submission is under review.

## 4. Share with Claude Code users

- [ ] Choose one relevant Claude-focused community and one social platform
      where we already participate.
- [ ] Read the current community rules on self-promotion and choose the right
      post category or sharing thread.
- [ ] Adapt the draft below to each audience and attach the demo.
- [ ] Publish the first post and record its URL.
- [ ] Make time to answer questions and help with installation.
- [ ] Collect feedback before deciding where to post next.

Draft post:

> I kept switching to another task whenever Claude Code was working, so I built
> Stay awhile: a small floating pixel-art landscape with ambient music and
> completion sounds.
>
> It has four animated scenes, usage information, and settings for music,
> volume, and the landscape right in the window. It's free and open source.
>
> Here's what it looks like. I'd love to hear whether it helps you stay with
> your current task—and whether anything about installation is confusing.
>
> https://github.com/sandorkan/stay-awhile

Use the personal story only if it accurately reflects the author's experience.
Keep the request specific: try it and share feedback, rather than just star it.

## 5. Reach the first 10 users and improve onboarding

- [ ] Gather feedback from 10 people who have actually tried the plugin.
- [ ] Note installation problems and turn reproducible problems into GitHub issues.
- [ ] Ask which scene or audio option they use and what makes them keep using it.
- [ ] Ask what feels distracting, confusing, or unnecessary.
- [ ] Fix repeated friction and update the documentation as needed.
- [ ] Share a small follow-up update explaining improvements made from feedback.

Measure this through voluntary replies and issue reports. Stars and views are
useful signals of interest, but do not establish that someone used the plugin.

## 6. Share on Show HN

Do this after a few people have installed it successfully and early installation
problems have been addressed.

- [ ] Re-read the [Show HN guidelines](https://news.ycombinator.com/showhn.html).
- [ ] Verify the repository and installation instructions are ready for new users.
- [ ] Submit a link to the repository with a clear title.
- [ ] Add an introductory comment explaining why it exists and how it works.
- [ ] Be available to answer technical questions and respond to feedback.

Suggested title:

> Show HN: Stay awhile – ambient sound and pixel-art landscapes for Claude Code

The introductory comment should cover the motivation, local viewer and hook
architecture, platform requirements, and known limitations. Invite people to
try it and discuss their experience.

## Launch log

Add a row whenever a release, submission, or post goes live. Record actual
outcomes rather than projected reach.

| Date | Action / channel | Link | Feedback and next step |
| --- | --- | --- | --- |
| 2026-09-21 | Updated GitHub description and added five discovery topics | [Repository](https://github.com/sandorkan/stay-awhile) | Prepare the first release; demo and fresh-install checks remain pending. |

## Feedback tracker

Use public handles or anonymous labels; avoid collecting unnecessary personal data.

| User / label | Installation result | Main feedback | Issue / follow-up |
| --- | --- | --- | --- |
| — | — | — | — |
