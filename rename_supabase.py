import os

def replace_in_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    new_content = content.replace('Sighting', 'Describe')
    new_content = new_content.replace('sighting', 'describe')
    new_content = new_content.replace('SIGHTING', 'DESCRIBE')
    
    if new_content != content:
        with open(filepath, 'w') as f:
            f.write(new_content)
        print(f"Updated {filepath}")

for root, _, files in os.walk('supabase'):
    for file in files:
        if file.endswith(('.ts', '.toml', '.sql')):
            replace_in_file(os.path.join(root, file))

