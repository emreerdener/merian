# Profile Shell

The `Shell` directory acts as the entry point and routing container for the Profile feature. 

## Structure

It primarily contains the top-level container, `ProfileView`, which is responsible for orchestrating the navigation and state between the different areas of the profile (such as the main User Profile tab and the Settings tab).

## Purpose
Following the Merian iOS architecture guidelines, the `Shell` isolates the routing, layout chrome, and tab-level coordination from the individual domain logic. This keeps `UserProfile` and `Settings` focused purely on their respective UI and logic without worrying about how they fit into the broader navigation hierarchy.
