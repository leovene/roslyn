﻿// Copyright (c) Microsoft.  All Rights Reserved.  Licensed under the Apache License, Version 2.0.  See License.txt in the project root for license information.

using System.Collections.Generic;
using System.Linq;
using Microsoft.CodeAnalysis;
using Microsoft.VisualStudio.OLE.Interop;

namespace Microsoft.VisualStudio.LanguageServices.Implementation.ProjectSystem
{
    internal partial class VisualStudioWorkspaceImpl
    {
        private abstract class AbstractRemoveDocumentUndoUnit : AbstractAddRemoveUndoUnit
        {
            protected readonly DocumentId DocumentId;

            protected AbstractRemoveDocumentUndoUnit(
                VisualStudioWorkspaceImpl workspace,
                DocumentId documentId)
                : base(workspace, documentId.ProjectId)
            {
                DocumentId = documentId;
            }

            protected abstract IReadOnlyList<DocumentId> GetDocumentIds(Project fromProject);

            protected abstract TextDocument GetDocument(Solution currentSolution);

            public override void Do(IOleUndoManager pUndoManager)
            {
                var currentSolution = Workspace.CurrentSolution;
                var fromProject = currentSolution.GetProject(FromProjectId);

                if (fromProject != null &&
                    GetDocumentIds(fromProject).Contains(DocumentId))
                {
                    var updatedProject = fromProject.RemoveDocument(DocumentId);
                    Workspace.TryApplyChanges(updatedProject.Solution);
                }
            }

            public override void GetDescription(out string pBstr)
            {
                var currentSolution = Workspace.CurrentSolution;
                var document = GetDocument(currentSolution);
                var documentName = document?.Name ?? "";
                pBstr = string.Format(FeaturesResources.Remove_document_0, documentName);
            }
        }
    }
}
