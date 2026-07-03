# Scans Library

The `Library` directory handles the primary grid view of all personal biological captures.

## Structure

- **Views**: Contains the main scan grid, search interfaces, and filtering menus.
- **ViewModels**: Handles the logic for semantic search, sorting (newest, oldest, alphabetical), and category filtering (Plants, Fungi, Insects, Birds, Mammals, Reptiles, Other).
- **Models**: Defines view-specific representations of scans and queued captures.

## Purpose
This is the core browsing experience for a user's identified biological scans. It includes the semantic search engine that can resolve plain-English queries against taxonomy, as well as handling the presentation of pending queued captures that haven't yet finished inference or upload.
