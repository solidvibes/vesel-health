status: idea

# A page sometimes opens with its top under the title bar

On the owner's iPhone 15 Pro (iOS 26.6), Loop & settings → Workouts sometimes opens scrolled down by the whole top bar: "Notice workouts by itself" sits behind the "Workouts" title until you scroll. It happens at random; other pages may do it too. It never happens in the Simulator (iOS 27). Two tries changed nothing: `.defaultScrollAnchor(.top, for: .sizeChanges)`, and scrolling to the top once the settings have loaded. Next step: test on an iOS 26 Simulator, or move the background from the `ZStack` into `.background` on the `ScrollView`, and check how the root's hidden navigation bar affects pushed pages.
