do {
                if let data = data {
                    let transcript = try await AudioManager.shared.transcribeFile(at: AudioManager.shared.audioFilename)
                    completion(.success(transcript))
                }
            } catch {
                completion(.failure(error))
            }