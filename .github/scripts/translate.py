import re
import sys
import time
from deep_translator import MyMemoryTranslator

def process_file(file_path):
    print(f"Reading {file_path}...")
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    pass_pattern = r'([а-яА-ЯёЁ]+(?:[\s\.,!?:-]*[а-яА-ЯёЁ0-9]+)*)'
    matches = list(set(re.findall(pass_pattern, content)))
    matches = [m for m in matches if len(m.strip()) > 1]
    
    if not matches:
        print(f"No Cyrillic text found in {file_path}.")
        return

    print(f"Found {len(matches)} unique phrases to translate.")
    
    translations = {}
    translator = MyMemoryTranslator(source='russian', target='english')
    
    batch_size = 50
    for i in range(0, len(matches), batch_size):
        batch = matches[i:i+batch_size]
        try:
            print(f"Translating batch {i//batch_size + 1} ({len(batch)} items)...")
            results = translator.translate_batch(batch)
            
            for original, translated in zip(batch, results):
                translations[original] = translated
            
            time.sleep(1) 
        except Exception as e:
            print(f"Error translating batch: {e}")
            for original in batch:
                 print(f"Failed to translate item: {original}")

    sorted_matches = sorted(translations.keys(), key=len, reverse=True)
    
    new_content = content
    for original in sorted_matches:
        translated = translations.get(original)
        if translated and translated != original:
             escaped_original = re.escape(original)
             new_content = re.sub(escaped_original, translated, new_content)

    if new_content != content:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Updated {file_path}")
    else:
        print(f"No changes made to {file_path}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python translate.py <file1> <file2> ...")
        sys.exit(1)

    for file_path in sys.argv[1:]:
        try:
            process_file(file_path)
        except Exception as e:
            print(f"Failed to process {file_path}: {e}")

if __name__ == "__main__":
    main()
