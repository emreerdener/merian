# User Profile

The `UserProfile` directory contains the user-facing screens and components that make up the main profile tab.

## Structure

- **Views**: Contains the primary view for this area, `ProfileTabView.swift`.
- **Components**: Contains reusable UI elements specific to the profile view, such as stats displays, achievement cards, heatmap graphs, and the recent scan grid.
- **Models**: Defines the data structures and domain logic exclusively needed for rendering the user's profile and gamification stats.
- **Utilities**: Helper functions and extensions tailored to profile data manipulation.

## Purpose
This product area is responsible for displaying the user's identity and progress. It presents the running species count, scan streaks, the 52-week rolling contribution heatmap, achievements, and user collections. It consumes state from the shared `ProfileViewModel`.
