using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CodeActions;
using Microsoft.CodeAnalysis.CodeFixes;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Text;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Composition;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace DiGi.Maintenance.Analyzers.CodeFixes
{
    /// <summary>
    /// CodeFixProvider for automatically reformatting parameter lists to satisfy the parameter line-break rule.
    /// </summary>
    [ExportCodeFixProvider(LanguageNames.CSharp, Name = nameof(ParameterListLineBreakCodeFixProvider)), Shared]
    public class ParameterListLineBreakCodeFixProvider : CodeFixProvider
    {
        private const string TitleSingleLine = "Reflow parameter list onto a single line";
        private const string TitleMultiLine = "Reflow parameter list onto multiple lines (one per line)";

        /// <summary>
        /// Gets a list of diagnostic IDs that this provider can fix.
        /// </summary>
        public override ImmutableArray<string> FixableDiagnosticIds
        {
            get
            {
                return ImmutableArray.Create(ParameterListLineBreakAnalyzer.DiagnosticId);
            }
        }

        /// <summary>
        /// Gets an optional FixAllProvider that can fix all occurrences of the diagnostic.
        /// </summary>
        /// <returns>The batch fix all provider.</returns>
        public override FixAllProvider GetFixAllProvider()
        {
            return WellKnownFixAllProviders.BatchFixer;
        }

        /// <summary>
        /// Computes one or more fixes for the specified diagnostic context.
        /// </summary>
        /// <param name="context">The code fix context containing diagnostic information.</param>
        /// <returns>A task representing the asynchronous operation.</returns>
        public override async Task RegisterCodeFixesAsync(CodeFixContext context)
        {
            SyntaxNode? root = await context.Document.GetSyntaxRootAsync(context.CancellationToken).ConfigureAwait(false);
            if (root == null)
            {
                return;
            }

            Diagnostic diagnostic = context.Diagnostics.First();
            TextSpan diagnosticSpan = diagnostic.Location.SourceSpan;

            ParameterListSyntax? parameterListSyntax = root.FindToken(diagnosticSpan.Start).Parent?.AncestorsAndSelf().OfType<ParameterListSyntax>().FirstOrDefault();
            if (parameterListSyntax == null)
            {
                return;
            }

            int parameterCount = parameterListSyntax.Parameters.Count;
            if (parameterCount <= 7)
            {
                context.RegisterCodeFix(
                    CodeAction.Create(
                        title: TitleSingleLine,
                        createChangedDocument: cancellationToken => ReflowToSingleLineAsync(context.Document, parameterListSyntax, cancellationToken),
                        equivalenceKey: TitleSingleLine),
                    diagnostic);
            }
            else
            {
                context.RegisterCodeFix(
                    CodeAction.Create(
                        title: TitleMultiLine,
                        createChangedDocument: cancellationToken => ReflowToMultiLineAsync(context.Document, parameterListSyntax, cancellationToken),
                        equivalenceKey: TitleMultiLine),
                    diagnostic);
            }
        }

        private static async Task<Document> ReflowToSingleLineAsync(Document document, ParameterListSyntax parameterListSyntax, CancellationToken cancellationToken)
        {
            SyntaxNode? root = await document.GetSyntaxRootAsync(cancellationToken).ConfigureAwait(false);
            if (root == null)
            {
                return document;
            }

            List<ParameterSyntax> listParameters_New = [];
            List<SyntaxToken> listSeparators_New = [];

            for (int i = 0; i < parameterListSyntax.Parameters.Count; i++)
            {
                ParameterSyntax parameterSyntax = parameterListSyntax.Parameters[i];
                ParameterSyntax parameterSyntax_Clean = parameterSyntax.WithLeadingTrivia().WithTrailingTrivia();
                listParameters_New.Add(parameterSyntax_Clean);

                if (i < parameterListSyntax.Parameters.Count - 1)
                {
                    SyntaxToken commaToken = SyntaxFactory.Token(SyntaxKind.CommaToken).WithTrailingTrivia(SyntaxFactory.Space);
                    listSeparators_New.Add(commaToken);
                }
            }

            SeparatedSyntaxList<ParameterSyntax> separatedList = SyntaxFactory.SeparatedList(listParameters_New, listSeparators_New);
            ParameterListSyntax parameterListSyntax_New = SyntaxFactory.ParameterList(separatedList)
                .WithOpenParenToken(SyntaxFactory.Token(SyntaxKind.OpenParenToken))
                .WithCloseParenToken(SyntaxFactory.Token(SyntaxKind.CloseParenToken))
                .WithLeadingTrivia(parameterListSyntax.GetLeadingTrivia())
                .WithTrailingTrivia(parameterListSyntax.GetTrailingTrivia());

            SyntaxNode root_New = root.ReplaceNode(parameterListSyntax, parameterListSyntax_New);
            return document.WithSyntaxRoot(root_New);
        }

        private static async Task<Document> ReflowToMultiLineAsync(Document document, ParameterListSyntax parameterListSyntax, CancellationToken cancellationToken)
        {
            SyntaxNode? root = await document.GetSyntaxRootAsync(cancellationToken).ConfigureAwait(false);
            if (root == null)
            {
                return document;
            }

            SyntaxTree? syntaxTree = await document.GetSyntaxTreeAsync(cancellationToken).ConfigureAwait(false);
            FileLinePositionSpan fileLineSpan = syntaxTree != null ? syntaxTree.GetLineSpan(parameterListSyntax.Span, cancellationToken) : default;

            SyntaxTriviaList leadingTrivia = parameterListSyntax.GetLeadingTrivia();
            string indentationBase = leadingTrivia.ToString().TrimStart('\r', '\n');
            string indentationParam = indentationBase + "    ";

            List<ParameterSyntax> listParameters_New = [];
            List<SyntaxToken> listSeparators_New = [];

            for (int i = 0; i < parameterListSyntax.Parameters.Count; i++)
            {
                ParameterSyntax parameterSyntax = parameterListSyntax.Parameters[i];
                ParameterSyntax parameterSyntax_Formatted = parameterSyntax
                    .WithLeadingTrivia(SyntaxFactory.CarriageReturnLineFeed, SyntaxFactory.Whitespace(indentationParam))
                    .WithTrailingTrivia();
                listParameters_New.Add(parameterSyntax_Formatted);

                if (i < parameterListSyntax.Parameters.Count - 1)
                {
                    SyntaxToken commaToken = SyntaxFactory.Token(SyntaxKind.CommaToken);
                    listSeparators_New.Add(commaToken);
                }
            }

            SyntaxToken openParenToken = SyntaxFactory.Token(SyntaxKind.OpenParenToken);
            SyntaxToken closeParenToken = SyntaxFactory.Token(SyntaxKind.CloseParenToken)
                .WithLeadingTrivia(SyntaxFactory.CarriageReturnLineFeed, SyntaxFactory.Whitespace(indentationBase));

            SeparatedSyntaxList<ParameterSyntax> separatedList = SyntaxFactory.SeparatedList(listParameters_New, listSeparators_New);
            ParameterListSyntax parameterListSyntax_New = SyntaxFactory.ParameterList(separatedList)
                .WithOpenParenToken(openParenToken)
                .WithCloseParenToken(closeParenToken)
                .WithLeadingTrivia(parameterListSyntax.GetLeadingTrivia())
                .WithTrailingTrivia(parameterListSyntax.GetTrailingTrivia());

            SyntaxNode root_New = root.ReplaceNode(parameterListSyntax, parameterListSyntax_New);
            return document.WithSyntaxRoot(root_New);
        }
    }
}
