import re

def fix_file(path):
    try:
        with open(path, "r") as f:
            content = f.read()
            
        # Strip trailing whitespace on lines
        lines = content.split('\n')
        lines = [line.rstrip() for line in lines]
        content = '\n'.join(lines)
        
        # Replace 3 or more newlines with 2 newlines
        content = re.sub(r'\n{3,}', '\n\n', content)
                
        with open(path, "w") as f:
            f.write(content)
        print(f"Fixed {path}")
    except Exception as e:
        print(f"Error fixing {path}: {e}")

fix_file("merian/Features/Insights/Views/InsightContentView.swift")
fix_file("merian/Features/Insights/ViewModels/InsightSheetViewModel.swift")

