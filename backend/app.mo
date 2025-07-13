import Bool "mo:base/Bool";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import HashMap "mo:map/Map";
import { phash; thash } "mo:map/Map";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Option "mo:base/Option";
import Error "mo:base/Error";
import Time "mo:base/Time"; // Added missing Time module

actor Filevault {
  // Define a data type for a file's chunks.
  type FileChunk = {
    chunk : Blob;
    index : Nat;
  };

  // Define a data type for a file's data.
  type File = {
    name : Text;
    chunks : [FileChunk];
    totalSize : Nat;
    fileType : Text;
    renewableProjectId : ?Text;  // Added for Renewables Vault integration
    uploadedAt : Int;            // Timestamp
  };

  // Define a data type for storing files associated with a user principal.
  type UserFiles = HashMap.Map<Text, File>;

  // HashMap to store the user data
  private stable var files = HashMap.new<Principal, UserFiles>();

  // Return files associated with a user's principal.
  private func getUserFiles(user : Principal) : UserFiles {
    switch (HashMap.get(files, phash, user)) {
      case null {
        let newFileMap = HashMap.new<Text, File>();
        ignore HashMap.put(files, phash, user, newFileMap);
        newFileMap;
      };
      case (?existingFiles) existingFiles;
    };
  };

  // Check if a file name already exists for the user.
  public shared (msg) func checkFileExists(name : Text) : async Bool {
    Option.isSome(HashMap.get(getUserFiles(msg.caller), thash, name));
  };

  // Upload a file in chunks with project association
  public shared (msg) func uploadFileChunk(
    name : Text,
    chunk : Blob,
    index : Nat,
    fileType : Text,
    renewableProjectId : ?Text  // Optional project association
  ) : async () {
    let userFiles = getUserFiles(msg.caller);
    let fileChunk = { chunk = chunk; index = index };

    switch (HashMap.get(userFiles, thash, name)) {
      case null {
        ignore HashMap.put(
          userFiles, 
          thash, 
          name, 
          { 
            name = name; 
            chunks = [fileChunk]; 
            totalSize = chunk.size(); 
            fileType = fileType;
            renewableProjectId = renewableProjectId;
            uploadedAt = Time.now(); // Fixed: Use Time.now()
          }
        );
      };
      case (?existingFile) {
        let updatedChunks = Array.append(existingFile.chunks, [fileChunk]);
        ignore HashMap.put(
          userFiles,
          thash,
          name,
          {
            name = name;
            chunks = updatedChunks;
            totalSize = existingFile.totalSize + chunk.size();
            fileType = fileType;
            renewableProjectId = existingFile.renewableProjectId; // Preserve existing project ID
            uploadedAt = existingFile.uploadedAt;
          }
        );
      };
    };
  };

  // Return list of files for a user with project metadata
  public shared (msg) func getFiles() : async [{
    name : Text; 
    size : Nat; 
    fileType : Text;
    projectId : ?Text;
    uploadedAt : Int;
  }] {
    Iter.toArray(
      Iter.map(
        HashMap.vals(getUserFiles(msg.caller)),
        func(file : File) : {
          name : Text; 
          size : Nat; 
          fileType : Text;
          projectId : ?Text;
          uploadedAt : Int;
        } {
          {
            name = file.name;
            size = file.totalSize;
            fileType = file.fileType;
            projectId = file.renewableProjectId;
            uploadedAt = file.uploadedAt;
          };
        }
      )
    );
  };

  // Get files by project ID
  public shared (msg) func getFilesByProject(projectId : Text) : async [File] {
    let userFiles = getUserFiles(msg.caller);
    let allFiles = Iter.toArray(HashMap.vals(userFiles));
    
    // Fixed: Properly filter files
    Array.filter(
      allFiles,
      func(file : File) : Bool {
        switch(file.renewableProjectId) {
          case null false;
          case (?id) id == projectId;
        }
      }
    )
  };

  // Return total chunks for a file
  public shared (msg) func getTotalChunks(name : Text) : async Nat {
    switch (HashMap.get(getUserFiles(msg.caller), thash, name)) {
      case null 0;
      case (?file) file.chunks.size();
    };
  };

  // Return specific chunk for a file.
  public shared (msg) func getFileChunk(name : Text, index : Nat) : async ?Blob {
    switch (HashMap.get(getUserFiles(msg.caller), thash, name)) {
      case null null;
      case (?file) {
        switch (Array.find(file.chunks, func(chunk : FileChunk) : Bool { chunk.index == index })) {
          case null null;
          case (?foundChunk) ?foundChunk.chunk;
        };
      };
    };
  };

  // Get file's type.
  public shared (msg) func getFileType(name : Text) : async ?Text {
    switch (HashMap.get(getUserFiles(msg.caller), thash, name)) {
      case null null;
      case (?file) ?file.fileType;
    };
  };

  // Delete a file.
  public shared (msg) func deleteFile(name : Text) : async Bool {
    Option.isSome(HashMap.remove(getUserFiles(msg.caller), thash, name));
  };

  // === Renewables Vault Specific Functions === //

  // Associate a file with a renewable energy project
  public shared (msg) func associateWithProject(name : Text, projectId : Text) : async Bool {
    let userFiles = getUserFiles(msg.caller);
    switch (HashMap.get(userFiles, thash, name)) {
      case null false;
      case (?file) {
        let updatedFile = {
          name = file.name;
          chunks = file.chunks;
          totalSize = file.totalSize;
          fileType = file.fileType;
          renewableProjectId = ?projectId;
          uploadedAt = file.uploadedAt;
        };
        ignore HashMap.put(userFiles, thash, name, updatedFile);
        true
      };
    };
  };

  // === Internet Identity Integration === //
  
  // Verify caller is authenticated
  func isAuthenticated(caller : Principal) : Bool {
    not Principal.isAnonymous(caller)
  };

  // Get user's renewable projects (placeholder - integrate with your project management)
  public shared (msg) func getRenewableProjects() : async [Text] {
    assert isAuthenticated(msg.caller);
    ["Benban-Solar-Egypt", "Sakaka-Wind-KSA", "Mohammed-bin-Rashid-Solar-UAE"]
  };

  // === File Management === //

  // Get file metadata
  public shared (msg) func getFileMetadata(name : Text) : async ?File {
    HashMap.get(getUserFiles(msg.caller), thash, name)
  };

  // Get storage usage (fixed implementation)
  public shared (msg) func getStorageUsage() : async Nat {
    let userFiles = getUserFiles(msg.caller);
    var total : Nat = 0;
    
    // Fixed: Iterate through files without complex mapping
    for (file in HashMap.vals(userFiles)) {
      total += file.totalSize;
    };
    total
  };

  system func preupgrade() {
    // Add serialization logic if needed for stable storage
  };

  system func postupgrade() {
    // Add deserialization logic if needed
  };
};