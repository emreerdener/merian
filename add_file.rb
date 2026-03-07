require 'xcodeproj'
project_path = 'Merian.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first
group = project.main_group.find_subpath('Merian/CoreServices', true)
file = group.new_file('InferenceEngine.swift')
target.source_build_phase.add_file_reference(file)
project.save
